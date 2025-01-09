-- Copyright 2024 Aarthi Perumpillichira
--
-- Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
--
-- 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
--
-- 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS “AS IS” AND ANY EXPRESS OR IMPLIED WARRANTIES,
-- INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
-- DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
-- SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
-- SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
-- WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE
-- USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
library work;
    use work.keccak_pkg.all;

entity keccak_axi4s is
    generic(
        g_lane_width : natural := 64; --1, 2, 4, 8, 16, 32 or 64
        g_data_width : natural := 64  --Power of 2, cannot be larger than word size
    );
    port(
        clock       : in  std_logic;
        reset       : in  std_logic;

        --Keccak function instance-specific data, read synchronously with first transfer of input data
        keccak_func : in  integer range 0 to c_num_functions;
        output_len  : in  natural; --In bytes

        --Data signals
        in_tdata    : in  std_logic_vector(g_data_width - 1 downto 0);
        in_tkeep    : in  std_logic_vector(g_data_width/8 - 1 downto 0);
        in_tlast    : in  std_logic;
        in_tvalid   : in  std_logic;
        in_tready   : out std_logic;
        out_tdata   : out std_logic_vector(g_data_width - 1 downto 0);
        out_tkeep   : out std_logic_vector(g_data_width/8 - 1 downto 0);
        out_tlast   : out std_logic;
        out_tvalid  : out std_logic;
        out_tready  : in  std_logic
    );
end entity;

architecture rtl of keccak_axi4s is
    constant c_state_size    : natural := g_lane_width * c_state_length * c_state_width;

    signal pad_in_tvalid     : std_logic;
    signal pad_in_tready     : std_logic;
    signal sponge_in_tdata   : std_logic_vector(g_data_width - 1 downto 0);
    signal sponge_in_tlast   : std_logic;
    signal sponge_in_tvalid  : std_logic;
    signal sponge_in_tready  : std_logic;
    signal sponge_out_tvalid : std_logic;

    signal bitrate           : natural; --range 0 to c_lane_width_max * c_state_length * c_state_width - 1;
    signal byterate          : natural; --range 0 to (c_lane_width_max/8) * c_state_length * c_state_width - 1;
    signal squeeze           : std_logic;
    signal postfix           : std_logic_vector(3 downto 0);
    signal postfix_len       : integer range 0 to 4;

    signal byte_counter      : integer;
    signal squeeze_len       : integer;

begin

    bitrate     <= c_bitrates(keccak_func) when keccak_func < c_num_functions else 0;
    byterate    <= bitrate/8;
    postfix     <= c_postfixes(keccak_func) when keccak_func < c_num_functions else (others => '0');
    postfix_len <= c_postfix_lengths(keccak_func) when keccak_func < c_num_functions else 0;

    i_pad: entity work.keccak_pad
        generic map(
            g_data_width => g_data_width
        ) port map(
            clock       => clock,
            reset       => reset,
            byterate    => byterate,
            postfix     => postfix,
            postfix_len => postfix_len,
            in_tdata    => in_tdata,
            in_tkeep    => in_tkeep,
            in_tlast    => in_tlast,
            in_tvalid   => pad_in_tvalid,
            in_tready   => pad_in_tready,
            out_tdata   => sponge_in_tdata,
            out_tlast   => sponge_in_tlast,
            out_tvalid  => sponge_in_tvalid,
            out_tready  => sponge_in_tready
        );

    pad_in_tvalid <= in_tvalid;
    in_tready     <= pad_in_tready;

    i_sponge: entity work.keccak_sponge
        generic map(
            g_lane_width => g_lane_width,
            g_data_width => g_data_width
        ) port map(
            clock      => clock,
            reset      => reset,
            rate       => bitrate,
            in_tdata   => sponge_in_tdata,
            in_tlast   => sponge_in_tlast,
            in_tvalid  => sponge_in_tvalid,
            in_tready  => sponge_in_tready,
            out_tdata  => out_tdata,
            out_tvalid => sponge_out_tvalid,
            out_tready => out_tready,
            squeeze    => squeeze
        );

    out_tvalid <= sponge_out_tvalid;
    out_tlast  <= '1' when byte_counter + (g_data_width/8) >= squeeze_len else '0';
    out_tkeep  <= std_logic_vector(to_unsigned(2**(squeeze_len - byte_counter) - 1, g_data_width/8)) when byte_counter + (g_data_width/8) >= squeeze_len else (others => '1');
    squeeze    <= '0' when (sponge_out_tvalid and out_tready) = '1' and byte_counter + (g_data_width/8) >= squeeze_len else '1';

    p_comb: process(keccak_func, output_len, byte_counter)
    begin
        case keccak_func is
            when c_func_sha3_224_idx | c_func_sha3_256_idx | c_func_sha3_384_idx | c_func_sha3_512_idx =>
                squeeze_len <= c_output_sizes(keccak_func)/8;
            when others =>
                squeeze_len <= output_len;
        end case;
    end process;

    p_clk: process(clock)
    begin
        if rising_edge(clock) then

            if sponge_out_tvalid = '1' and out_tready = '1' then
                if byte_counter + (g_data_width/8) >= squeeze_len then
                    byte_counter <= 0;
                else
                    byte_counter <= byte_counter + (g_data_width/8);
                end if;
            end if;

            if reset = '1' then
                byte_counter <= 0;
            end if;
        end if;
    end process;

end architecture;
