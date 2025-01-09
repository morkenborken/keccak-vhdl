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


-- Absorbs data until in_tlast is asserted, then squeezes data until squeeze is deasserted
entity keccak_sponge is
    generic(
        g_lane_width : natural := 64; --1, 2, 4, 8, 16, 32 or 64
        g_data_width : natural := 64  --Power of 2, cannot be larger than word size
    );
    port(
        clock       : in  std_logic;
        reset       : in  std_logic;
        rate        : in  natural; --Read when the first transfer of the input is absorbed
        in_tdata    : in  std_logic_vector(g_data_width - 1 downto 0); --Data is expected to be padded
        in_tlast    : in  std_logic;
        in_tvalid   : in  std_logic;
        in_tready   : out std_logic;
        out_tdata   : out std_logic_vector(g_data_width - 1 downto 0);
        out_tvalid  : out std_logic;
        out_tready  : in  std_logic;
        squeeze     : in  std_logic  --Pull low when finished squeezing, last output will come the cycle after it is pulled low
    );
end entity;

architecture rtl of keccak_sponge is
    type t_control is (st_idle, st_absorb, st_realign_absorb, st_realign_squeeze,
                       st_permutate_absorb, st_permutate_squeeze, st_squeeze);

    constant c_state_size : natural := g_lane_width * c_state_length * c_state_width;

    function log2(x : integer) return integer is
        variable x_temp : integer;
        variable log2_x : integer;
    begin
        x_temp := x;
        log2_x := 0;
        while x_temp > 1 loop
            log2_x := log2_x + 1;
            x_temp := x_temp/2;
        end loop;
        return log2_x;
    end function;

    type t_state_row is array (0 to c_state_width - 1) of std_logic_vector(g_lane_width - 1 downto 0);
    type t_state_array is array (0 to c_state_length - 1) of t_state_row;

    constant c_round_count   : natural := 12 + 2 * log2(g_lane_width);
    constant c_rotate_count  : natural := c_state_size/g_data_width;
    signal state             : std_logic_vector(c_state_size - 1 downto 0); --Fully in registers
    signal state_next        : std_logic_vector(c_state_size - 1 downto 0); --Not in registers
    signal bit_counter       : integer range 0 to c_state_size;
    signal rotate_counter    : integer range 0 to c_rotate_count - 1;
    signal round_counter     : integer range 0 to c_max_rounds - 1;
    signal rate_buf          : integer range 0 to c_state_size;
    signal control           : t_control;
    signal out_tvalid_i      : std_logic;

    --Only used for debugging
    signal unpacked          : t_state_array;
    signal a                 : t_state_array;
    signal b                 : t_state_array;
    signal c                 : t_state_row;
    signal d                 : t_state_row;

    signal theta             : t_state_array;
    signal rho_pi            : t_state_array;
    signal chi               : t_state_array;

begin

    in_tready  <= '1' when control = st_idle or control = st_absorb else '0';
    out_tvalid <= out_tvalid_i;

    p_state: process(clock)
    begin
        if rising_edge(clock) then
            if out_tready = '1' then
                out_tvalid_i <= '0';
            end if;

            case control is
            when st_idle =>
                if in_tvalid = '1' and (out_tvalid_i = '0' or out_tready = '1') then
                    state(c_state_size - 1 downto c_state_size - g_data_width) <= state(g_data_width - 1 downto 0) xor in_tdata;
                    bit_counter                                                <= rate - (g_data_width * 2);
                    rotate_counter                                             <= c_rotate_count - 2;
                    round_counter                                              <= c_round_count - 1;
                    rate_buf                                                   <= rate;
                    control                                                    <= st_absorb;
                end if;

            when st_absorb =>
                if in_tvalid = '1' then
                    state          <= (state(g_data_width - 1 downto 0) xor in_tdata) & state(c_state_size - 1 downto g_data_width);
                    rotate_counter <= rotate_counter - 1;
                    if bit_counter = 0 then
                        bit_counter <= rate_buf - g_data_width;
                        if in_tlast = '1' then
                            control <= st_realign_squeeze;
                        else
                            control <= st_realign_absorb;
                        end if;
                    else
                        bit_counter <= bit_counter - g_data_width;
                    end if;
                end if;

            when st_realign_absorb | st_realign_squeeze =>
                state <= state(g_data_width - 1 downto 0) & state(c_state_size - 1 downto g_data_width);
                if rotate_counter = 0 then
                    rotate_counter <= c_rotate_count - 1;
                    if control = st_realign_squeeze then
                        control <= st_permutate_squeeze;
                    else
                        control <= st_permutate_absorb;
                    end if;
                else
                    rotate_counter <= rotate_counter - 1;
                end if;

            when st_permutate_absorb | st_permutate_squeeze =>
                state <= state_next;
                if round_counter = 0 then
                    round_counter <= c_round_count - 1;
                    if control = st_permutate_squeeze then
                        control <= st_squeeze;
                    else
                        control <= st_absorb;
                    end if;
                else
                    round_counter <= round_counter - 1;
                end if;

            when st_squeeze =>
                if out_tvalid_i = '0' or out_tready = '1' then
                    rotate_counter <= rotate_counter - 1;
                    state          <= state(g_data_width - 1 downto 0) & state(c_state_size - 1 downto g_data_width);
                    out_tvalid_i   <= squeeze;
                    out_tdata      <= state(g_data_width - 1 downto 0);
                    if squeeze = '0' then
                        state   <= (others => '0');
                        control <= st_idle;
                    elsif bit_counter = 0 then
                        bit_counter <= rate_buf - g_data_width;
                        control     <= st_realign_squeeze;
                    else
                        bit_counter <= bit_counter - g_data_width;
                    end if;
                end if;
            end case;

            if reset = '1' then
                state          <= (others => '0');
                bit_counter    <= 0;
                rotate_counter <= 0;
                round_counter  <= 0;
                rate_buf       <= 0;
                control        <= st_idle;
                out_tvalid_i   <= '0';
            end if;
        end if;
    end process;

    p_permutate: process(state, round_counter)
        variable v_a            : t_state_array;
        variable v_b            : t_state_array;
        variable v_c            : t_state_row;
        variable v_d            : t_state_row;
        variable v_lane_offset  : integer;
    begin
        --Unpack state
        for i in 0 to c_state_length - 1 loop
            for j in 0 to c_state_width - 1 loop
                v_lane_offset := ((j * c_state_width) + i) * g_lane_width;
                v_a(i)(j)     := state(v_lane_offset + g_lane_width - 1 downto v_lane_offset);
            end loop;
        end loop;

        unpacked <= v_a;

        --C[x] = A[x,0] xor A[x,1] xor A[x,2] xor A[x,3] xor A[x,4],   for x in 0…4
        for i in 0 to c_state_length - 1 loop
            v_c(i) := v_a(i)(0);
            for j in 1 to c_state_width - 1 loop
                v_c(i) := v_c(i) xor v_a(i)(j);
            end loop;
        end loop;

        --D[x] = C[x-1] xor rot(C[x+1],1),                             for x in 0…4
        for i in 0 to c_state_length - 1 loop
            v_d(i) := v_c((i - 1) mod c_state_length) xor
                std_logic_vector((unsigned(v_c((i + 1) mod 5)) rol 1));
        end loop;

        --A[x,y] = A[x,y] xor D[x],                           for (x,y) in (0…4,0…4)
        for i in 0 to c_state_length - 1 loop
            for j in 0 to c_state_width - 1 loop
                v_a(i)(j) := v_a(i)(j) xor v_d(i);
            end loop;
        end loop;

        theta <= v_a;

        --B[y,2*x+3*y] = rot(A[x,y], r[x,y]),                 for (x,y) in (0…4,0…4)
        for i in 0 to c_state_length - 1 loop
            for j in 0 to c_state_width - 1 loop
                v_b(j)((2 * i + 3 * j) mod c_state_width) :=
                    std_logic_vector(unsigned(v_a(i)(j)) rol c_rotation_offsets(i)(j));
            end loop;
        end loop;

        rho_pi <= v_b;

        --A[x,y] = B[x,y] xor ((not B[x+1,y]) and B[x+2,y]),  for (x,y) in (0…4,0…4)
        for i in 0 to c_state_length - 1 loop
            for j in 0 to c_state_width - 1 loop
                v_a(i)(j) := v_b(i)(j) xor ((not v_b((i + 1) mod c_state_length)(j)) and v_b((i + 2) mod c_state_length)(j));
            end loop;
        end loop;

        chi <= v_a;

        --A[0,0] = A[0,0] xor RC
        v_a(0)(0) := v_a(0)(0) xor c_round_constants(c_max_rounds - (round_counter + 1));

        a <= v_a;
        b <= v_b;
        c <= v_c;
        d <= v_d;

        --Pack state
        for i in 0 to c_state_length - 1 loop
            for j in 0 to c_state_width - 1 loop
                v_lane_offset := ((j * c_state_width) + i) * g_lane_width;
                state_next(v_lane_offset + g_lane_width - 1 downto v_lane_offset) <= v_a(i)(j);
            end loop;
        end loop;
    end process;

end architecture;