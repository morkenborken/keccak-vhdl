#!/user/bin/python3

# Copyright 2024 Aarthi Perumpillichira
#
# Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS “AS IS” AND ANY EXPRESS OR IMPLIED WARRANTIES,
# INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE
# USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
import random
import cocotb
import logging
import sys
import random

from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from cocotbext.axi import AxiStreamBus, AxiStreamSource, AxiStreamSink

from Cryptodome.Hash import SHA3_224, SHA3_256, SHA3_384, SHA3_512, SHAKE128, SHAKE256

FUNC_SHA3_224     = 0
FUNC_SHA3_256     = 1
FUNC_SHA3_384     = 2
FUNC_SHA3_512     = 3
FUNC_SHAKE_128    = 4
FUNC_SHAKE_256    = 5
FUNC_RAWSHAKE_128 = 6
FUNC_RAWSHAKE_256 = 7
FUNC_KECCAK_128   = 8
FUNC_KECCAK_256   = 9
FUNC_KECCAK_512   = 10

def keccak_pad(input, byterate):
    if len(input) % byterate == byterate - 1:
        input += bytes([0x81])
    else:
        input += bytes([0x01])
        input += bytes(byterate - (len(input) % byterate) - 1)
        input += bytes([0x80])

    return input

@cocotb.test()
async def testcase(dut):
    """Test the keccak core"""

    in_source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "in"), dut.clock, dut.reset)
    out_sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "out"), dut.clock, dut.reset)
    in_source.log.setLevel(logging.WARN)
    out_sink.log.setLevel(logging.WARN)
    logger = logging.getLogger(__name__)
    logger.setLevel(logging.INFO)

    #Clock and reset
    clock = Clock(dut.clock, 10, units="ns")
    await cocotb.start(clock.start())
    dut.reset.value = 1
    for _ in range(3):
        await RisingEdge(dut.clock)
    dut.reset.value = 0
    await RisingEdge(dut.clock)

    for i in range(6):
        for j in range(10):
            random.seed(j)
            input_bytes = bytes(range(j + 1))
            output_reference = bytes(0)
            output_len = j + 1
            if i == FUNC_SHA3_224:
                output_reference = SHA3_224.new(data=input_bytes).digest()
            elif i == FUNC_SHA3_256:
                output_reference = SHA3_256.new(data=input_bytes).digest()
            elif i == FUNC_SHA3_384:
                output_reference = SHA3_384.new(data=input_bytes).digest()
            elif i == FUNC_SHA3_512:
                output_reference = SHA3_512.new(data=input_bytes).digest()
            elif i == FUNC_SHAKE_128:
                output_reference = SHAKE128.new(data=input_bytes).read(output_len)
            elif i == FUNC_SHAKE_256:
                output_reference = SHAKE256.new(data=input_bytes).read(output_len)

            dut.keccak_func.value = i
            dut.output_len.value = output_len
            await in_source.send(input_bytes)
            output = (await out_sink.recv()).tdata

            logger.info("Received output")
            logger.info(output.hex())
            logger.info("Reference output")
            logger.info(output_reference.hex())

            assert output.hex() == output_reference.hex()

    for _ in range(3):
        await RisingEdge(dut.clock)