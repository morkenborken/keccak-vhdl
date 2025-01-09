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

entity keccak_pad is
    generic(
        g_lane_width : natural := 64; --1, 2, 4, 8, 16, 32 or 64
        g_data_width : natural := 64  --Power of 2, cannot be larger than word size
    );
    port(
        clock       : in  std_logic;
        reset       : in  std_logic;

        --Keccak function instance-specific data, read synchronously with first transfer of input data
        byterate    : in  natural;
        postfix     : in  std_logic_vector(c_postfix_max_len - 1 downto 0);
        postfix_len : in  natural range 0 to c_postfix_max_len;

        --Data signals
        in_tdata    : in  std_logic_vector(g_data_width - 1 downto 0);
        in_tkeep    : in  std_logic_vector(g_data_width/8 - 1 downto 0);
        in_tlast    : in  std_logic;
        in_tvalid   : in  std_logic;
        in_tready   : out std_logic;
        out_tdata   : out std_logic_vector(g_data_width - 1 downto 0);
        out_tlast   : out std_logic;
        out_tvalid  : out std_logic;
        out_tready  : in  std_logic
    );
end entity;

architecture rtl of keccak_pad is
    type t_control is (st_passthrough, st_pad);

    signal byte_counter      : integer range 0 to (c_lane_width_max * c_state_length * c_state_width - 1)/8 - 1;
    signal control           : t_control;
    signal pad_first         : std_logic;
    signal pad_first_byte    : std_logic_vector(7 downto 0);
    signal pad_one_byte      : std_logic_vector(7 downto 0);
    signal out_tvalid_i      : std_logic;

begin

    in_tready  <= out_tready or not out_tvalid_i when control = st_passthrough else '0';
    out_tvalid <= out_tvalid_i;

    p_pad_bytes: process(postfix, postfix_len)
    begin
        pad_first_byte                           <= (others => '0');
        pad_first_byte(postfix_len)              <= '1';
        pad_first_byte(postfix_len - 1 downto 0) <= postfix(postfix_len - 1 downto 0);
        pad_one_byte                             <= (others => '0');
        pad_one_byte(7)                          <= '1';
        pad_one_byte(postfix_len)                <= '1';
        pad_one_byte(postfix_len - 1 downto 0)   <= postfix(postfix_len - 1 downto 0);
    end process;

    p_state: process(clock)
    begin
        if rising_edge(clock) then
            if out_tready = '1' then
                out_tvalid_i <= '0';
            end if;

            case control is
            when st_passthrough =>
                if in_tvalid = '1' and (out_tvalid_i = '0' or out_tready = '1') then
                    out_tvalid_i <= '1';
                    out_tdata    <= in_tdata;
                    out_tlast    <= '0';

                    if byte_counter = byterate - g_data_width/8 then
                        byte_counter <= 0;
                    else
                        byte_counter <= byte_counter + g_data_width/8;
                    end if;

                    if in_tlast = '1' then
                        if (byte_counter = byterate - g_data_width/8 and in_tkeep(g_data_width/8 - 1) = '1') or
                           byte_counter /= byterate - g_data_width/8 then
                            control <= st_pad;
                        else
                            out_tlast <= '1';
                        end if;

                        if in_tkeep(g_data_width/8 - 1) = '1' then
                            pad_first <= '1';
                        else
                            for i in 0 to g_data_width/8 - 1 loop
                                if in_tkeep(i) = '1' then
                                    out_tdata((i + 1) * 8 - 1 downto i * 8) <= in_tdata((i + 1) * 8 - 1 downto i * 8);
                                elsif in_tkeep(i - 1) = '1' then
                                    if byte_counter = byterate - g_data_width/8 and i = g_data_width/8 - 1 then
                                        out_tdata((i + 1) * 8 - 1 downto i * 8) <= pad_one_byte;
                                    else
                                        out_tdata((i + 1) * 8 - 1 downto i * 8) <= pad_first_byte;
                                    end if;
                                elsif byte_counter = byterate - g_data_width/8 and i = g_data_width/8 - 1 then
                                    out_tdata((i + 1) * 8 - 1 downto i * 8) <= x"80";
                                else
                                    out_tdata((i + 1) * 8 - 1 downto i * 8) <= (others => '0');
                                end if;
                            end loop;
                        end if;
                    end if;
                end if;

            when st_pad =>
                if out_tvalid_i = '0' or out_tready = '1' then
                    out_tvalid_i <= '1';
                    out_tdata    <= (others => '0');

                    if pad_first = '1' then
                        out_tdata(7 downto 0) <= pad_first_byte;
                        pad_first             <= '0';
                    end if;

                    if byte_counter = byterate - g_data_width/8 then
                        out_tlast                   <= '1';
                        control                     <= st_passthrough;
                        byte_counter                <= 0;
                        out_tdata(g_data_width - 1) <= '1';
                    else
                        byte_counter <= byte_counter + g_data_width/8;
                    end if;
                end if;
            end case;

            if reset = '1' then
                out_tvalid_i   <= '0';
                control        <= st_passthrough;
                byte_counter   <= 0;
                pad_first      <= '0';
            end if;
        end if;
    end process;

end architecture;
