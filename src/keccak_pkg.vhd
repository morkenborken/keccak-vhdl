-- Copyright 2024 Aarthi Perumpillichira
--
-- Redistribution and use in source and binary forms, with or without modification, are permitted provided that the
-- following conditions are met:
--
-- 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following
--    disclaimer.
--
-- 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the
--    following disclaimer in the documentation and/or other materials provided with the distribution.
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
    use ieee.math_real.all;

package keccak_pkg is

    constant c_state_width      : natural := 5;
    constant c_state_length     : natural := 5;
    constant c_lane_width_max   : natural := 64;
    constant c_max_rounds       : natural := 24;
    constant c_postfix_max_len  : natural := 4;

    type t_integer_array is array (integer range <>) of integer;
    type t_postfix_array is array (integer range <>) of std_logic_vector(c_postfix_max_len - 1 downto 0);
    type t_rc_vec is array (0 to c_max_rounds - 1) of std_logic_vector(c_lane_width_max - 1 downto 0);
    type t_rot_offset_vec is array (0 to c_state_width - 1) of integer;
    type t_rot_offset_mat is array (0 to c_state_length - 1) of t_rot_offset_vec;

    constant c_num_functions              : integer := 11;
    constant c_num_fixed_output_functions : integer := 4;

    constant c_func_sha3_224_idx     : integer := 0;
    constant c_func_sha3_256_idx     : integer := 1;
    constant c_func_sha3_384_idx     : integer := 2;
    constant c_func_sha3_512_idx     : integer := 3;
    constant c_func_shake_128_idx    : integer := 4;
    constant c_func_shake_256_idx    : integer := 5;
    constant c_func_rawshake_128_idx : integer := 6;
    constant c_func_rawshake_256_idx : integer := 7;
    constant c_func_keccak_128_idx   : integer := 8;
    constant c_func_keccak_256_idx   : integer := 9;
    constant c_func_keccak_512_idx   : integer := 10;

    constant c_output_sizes : t_integer_array(0 to c_num_fixed_output_functions - 1) := (
        c_func_sha3_224_idx     => 224,
        c_func_sha3_256_idx     => 256,
        c_func_sha3_384_idx     => 384,
        c_func_sha3_512_idx     => 512
    );

    constant c_bitrates              : t_integer_array(0 to c_num_functions - 1) := (
        c_func_sha3_224_idx     => 1152,
        c_func_sha3_256_idx     => 1088,
        c_func_sha3_384_idx     => 832,
        c_func_sha3_512_idx     => 576,
        c_func_shake_128_idx    => 1344,
        c_func_shake_256_idx    => 1088,
        c_func_rawshake_128_idx => 1344,
        c_func_rawshake_256_idx => 1088,
        c_func_keccak_128_idx   => 1472,
        c_func_keccak_256_idx   => 1344,
        c_func_keccak_512_idx   => 1088
    );

    constant c_postfixes             : t_postfix_array(0 to c_num_functions - 1) := (
        c_func_sha3_224_idx     => x"2",
        c_func_sha3_256_idx     => x"2",
        c_func_sha3_384_idx     => x"2",
        c_func_sha3_512_idx     => x"2",
        c_func_shake_128_idx    => x"f",
        c_func_shake_256_idx    => x"f",
        c_func_rawshake_128_idx => x"3",
        c_func_rawshake_256_idx => x"3",
        c_func_keccak_128_idx   => x"0",
        c_func_keccak_256_idx   => x"0",
        c_func_keccak_512_idx   => x"0"
    );

    constant c_postfix_lengths       : t_integer_array(0 to c_num_functions - 1) := (
        c_func_sha3_224_idx     => 2,
        c_func_sha3_256_idx     => 2,
        c_func_sha3_384_idx     => 2,
        c_func_sha3_512_idx     => 2,
        c_func_keccak_128_idx   => 0,
        c_func_keccak_256_idx   => 0,
        c_func_keccak_512_idx   => 0,
        c_func_rawshake_128_idx => 2,
        c_func_rawshake_256_idx => 2,
        c_func_shake_128_idx    => 4,
        c_func_shake_256_idx    => 4
    );

    constant c_round_constants  : t_rc_vec :=
        (
            x"0000000000000001",
            x"0000000000008082",
            x"800000000000808A",
            x"8000000080008000",
            x"000000000000808B",
            x"0000000080000001",
            x"8000000080008081",
            x"8000000000008009",
            x"000000000000008A",
            x"0000000000000088",
            x"0000000080008009",
            x"000000008000000A",
            x"000000008000808B",
            x"800000000000008B",
            x"8000000000008089",
            x"8000000000008003",
            x"8000000000008002",
            x"8000000000000080",
            x"000000000000800A",
            x"800000008000000A",
            x"8000000080008081",
            x"8000000000008080",
            x"0000000080000001",
            x"8000000080008008"
        );

    --Transposed as the permutation loop is transposed as well
    constant c_rotation_offsets : t_rot_offset_mat :=
        (
            (0, 36, 3, 41, 18),
            (1, 44, 10, 45, 2),
            (62, 6, 43, 15, 61),
            (28, 55, 25, 21, 56),
            (27, 20, 39, 8, 14)
        );

    function get_num_rounds(lane_width : natural) return natural;

end package;

package body keccak_pkg is
    function get_num_rounds(lane_width : natural) return natural is
        variable ret    : natural;
    begin
        case lane_width is
        when 1 =>
            return 12;
        when 2 =>
            return 14;
        when 4 =>
            return 16;
        when 8 =>
            return 18;
        when 16 =>
            return 20;
        when 32 =>
            return 22;
        when others =>
            return 24;
        end case;
    end function;
end keccak_pkg;