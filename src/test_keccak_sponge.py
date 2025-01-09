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

from CompactFIPS202 import Keccak

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
    for i in range(10):
        random.seed(i)
        bitrate = 512 + i * 64
        dut.rate.value = bitrate
        input = [random.getrandbits(64) for _ in range(bitrate//64)]
        input_bytes = bytes(0)
        for transfer in input:
            input_bytes += transfer.to_bytes(8, 'little')
        await in_source.send(keccak_pad(input_bytes, bitrate//8))

        dut.squeeze.value = 1
        if dut.out_tvalid.value == 0:
            await RisingEdge(dut.out_tvalid)
        output = bytes(0)
        for _ in range(i + 1):
            await RisingEdge(dut.clock)
        dut.squeeze.value = 0

        for _ in range(10):
            await RisingEdge(dut.clock)

        while not out_sink.queue.empty():
            output += (await out_sink.recv()).tdata

        output_reference = Keccak(bitrate, 1600 - bitrate, input_bytes, 0x01, len(output))

        logger.info("Received output")
        logger.info(output.hex())
        logger.info("Reference output")
        logger.info(output_reference.hex())

        assert output.hex() == output_reference.hex()
