# File:    test.py
# Author:  Yorimichi
# Date:    2025-11-03
# Version: 1.0
# Brief:   Testbench for KITT Scanner Project
# 
# Copyright (c) 2025- Yorimichi
# License: Apache-2.0
# 
# Revision History:
#   1.0 - Initial release
# 
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer

async def info_time(dut):
    while True:
        await Timer(1, 'ms')  # Wait for 1 ms
        dut._log.info("Simulation time: %s ms", cocotb.utils.get_sim_time('ms'))

class debouncer_model:
    
    def __init__(self, dut, sample_interval=100):
        self.state = 0
        self.sample_interval = sample_interval
        self.counter = 0
        self.sample = [0, 0, 0]
        self.sync_in0 = 0
        self.sync_in1 = 0
        self.sync_out = 0
        self.dut = dut
        self.sync_out_d = 0

    def reset(self):
        self.state = 0
        self.counter = 0
        self.sync_in0 = 0
        self.sync_in1 = 0
        self.sample = [0, 0, 0]
        self.sync_out = 0
        self.sync_out_d = 0

    def update(self):
        if(self.dut.rst_n.value == 0):
            self.reset()
        else:
            self.sync_out_d = self.sync_out # Flip flop for output
            match (self.state):
                case 0: # reset sync0
                    self.state = 1
                case 1: # reset sync1
                    self.state = 2
                case 2: # count up
                    # debouncing logic
                    if([self.sample[0], self.sample[1], self.sample[2]] == [1, 1, 1]):
                        self.sync_out = 1
                        
                    elif([self.sample[0], self.sample[1], self.sample[2]] == [0, 0, 0]):
                        self.sync_out = 0
                    # sampling logic
                    if(self.counter == self.sample_interval - 1):                        
                        self.counter = 0
                        self.sample[2] = self.sample[1]
                        self.sample[1] = self.sample[0]
                        self.sample[0] = self.sync_in1
                        print(f"Sampled: {self.sample}")                        
                    else:
                        self.counter += 1
                    # synchronizer logic
                    self.sync_in1 = self.sync_in0
                    self.sync_in0 = self.dut.ui_in.value[0] 
                        
        return self.sync_out_d

class kitt_scanner_model:
    def __init__(self, dut, speedl = 1500000, speedh = 1000000, pwm_period=1000, pwm_duty0=250, pwm_duty1=100, pwm_duty2=50):
        self.dut = dut
        self.ena = 0
        self.state = 0
        self.speedl = speedl
        self.speedh = speedh
        self.pwm_period = pwm_period
        self.pwm_duty0 = pwm_duty0
        self.pwm_duty1 = pwm_duty1
        self.pwm_duty2 = pwm_duty2
        self.pwm0 = 0 #25%
        self.pwm1 = 0 #10%
        self.pwm2 = 0 #5%
        self.pre_pwmout = [0,0,0,0,0,0,0,0]
        self.pre_ledout = [0,0,0,0,0,0,0,0]
        self.pwmout = [0,0,0,0,0,0,0,0]
        self.ledout = [0,0,0,0,0,0,0,0]

        self.speed = 0 # 0: slow, 1: fast
        self.mode = 0 # 0: single, 1: pingpong, 2: random
        self.osel = 0 # 0: LEDOUT, 1: PWMOUT
        self.oinv = 0 # 0: normal, 1: inverted
        self.pwm_counter = 0
        self.counter = 0
        self.pre_update_state = False

    def reset(self):        
        self.ena = 0
        self.state = 0
        self.speed = 0 # 0: slow, 1: fast
        self.mode = 0 # 0: single, 1: pingpong, 2: random
        self.osel = 0 # 0: LEDOUT, 1: PWMOUT
        self.oinv = 0 # 0: normal, 1: inverted
        self.pwm_counter = 0
        self.counter = 0
        self.pwm0 = 0 #25%
        self.pwm1 = 0 #10%
        self.pwm2 = 0 #5%
        self.pre_pwmout = [0,0,0,0,0,0,0,0]
        self.pre_ledout = [0,0,0,0,0,0,0,0]
        self.pwmout = [0,0,0,0,0,0,0,0]
        self.ledout = [0,0,0,0,0,0,0,0]

        self.pre_update_state = False

    def update(self, sync_en_out):
        update_state = False
        self.ena = sync_en_out

        if(self.dut.rst_n.value == 0):
            self.reset()
        else:
            for i in range(8):
                tmp_led = self.pre_pwmout[i] if self.osel != 0 else self.pre_ledout[i]
                tmp_pwm = self.pre_pwmout[i]

                if(self.oinv == 1):
                    tmp_pwm = 1 if tmp_pwm == 0 else 0
                    tmp_led = 1 if tmp_led == 0 else 0

                self.pwmout[i] = tmp_pwm
                self.ledout[i] = tmp_led
                
            # PWM generation
            pre_pwm0 = self.pwm0
            pre_pwm1 = self.pwm1
            pre_pwm2 = self.pwm2
            if(self.state != 0 and self.state != 1): # not IDLE and CAPTURE
                if(self.pwm_counter == 0):
                    self.pwm0 = 1
                    self.pwm1 = 1
                    self.pwm2 = 1
                
                if(self.pwm_counter == self.pwm_duty0-1):
                    self.pwm0 = 0
                if(self.pwm_counter == self.pwm_duty1-1):
                    self.pwm1 = 0
                if(self.pwm_counter == self.pwm_duty2-1):
                    self.pwm2 = 0
            else:  
                self.pwm0 = 0
                self.pwm1 = 0
                self.pwm2 = 0

            if(self.ena != 0):
                if(self.state !=0 and self.state != 1): # not IDLE adnd CAPTURE
                    if(self.pwm_counter < self.pwm_period-1):
                        self.pwm_counter += 1
                    else:
                        self.pwm_counter =0
            else :
                self.pwm_counter = 0

            # light shift timer
            if(self.ena != 0):
                if(self.state == 1): #CAPTURE
                    self.counter = self.speedl if self.speed == 0 else self.speedh
                else:
                    if(self.counter > 0):
                        self.counter -= 1
                    else:
                        update_state = True
                        self.counter = self.speedl - 1 if self.speed == 0 else self.speedh - 1

            # state control
            if(self.ena == 0):
                self.state = 0 # IDLE
                self.pre_pwmout = [0,0,0,0,0,0,0,0]

            else:
                match (self.state):
                    case 0: #IDLE
                        if(self.ena == 1):
                            self.speed = self.dut.ui_in.value[3]
                            self.mode = (int(self.dut.ui_in.value[2]) << 1) + int(self.dut.ui_in.value[1])
                            self.osel = self.dut.ui_in.value[5]
                            self.oinv = self.dut.ui_in.value[4]
                            self.pre_pwmout = [0,0,0,0,0,0,0,0]
                            self.state = 1
                            print("IDLE -> CAPTURE")
                    case 1: #CAPTURE
                        match(self.mode):
                            case 0: 
                                self.state = 10
                                print("CAPTURE -> %d", self.state)
                            case _:
                                pass
                    case 10:
                        self.pre_pwmout = [1, 0, 0, 0, 0, 0, 0, 0]
                        if(update_state):
                            self.state += 1
                            self.pre_pwmout = [pre_pwm0, 1, 0, 0, 0, 0, 0, 0]
                    case 11:
                        self.pre_pwmout = [pre_pwm0, 1, 0, 0, 0, 0, 0, 0]
                        if(update_state):
                            self.state += 1
                            self.pre_pwmout = [pre_pwm1, pre_pwm0, 1, 0, 0, 0, 0, 0]    
                    case 12:
                        self.pre_pwmout = [pre_pwm1, pre_pwm0, 1, 0, 0, 0, 0, 0]
                        if(update_state):
                            self.state += 1
                            self.pre_pwmout = [pre_pwm2, pre_pwm1, pre_pwm0, 1, 0, 0, 0, 0]
                    case 13:
                        self.pre_pwmout = [pre_pwm2, pre_pwm1, pre_pwm0, 1, 0, 0, 0, 0]
                        if(update_state):
                            self.state += 1
                            self.pre_pwmout = [0, pre_pwm2, pre_pwm1, pre_pwm0, 1, 0, 0, 0]
                    case 14:
                        self.pre_pwmout = [0, pre_pwm2, pre_pwm1, pre_pwm0, 1, 0, 0, 0]
                        if(update_state):
                            self.state += 1
                            self.pre_pwmout = [0, 0, pre_pwm2, pre_pwm1, pre_pwm0, 1, 0, 0]
                    case 15:
                        self.pre_pwmout = [0, 0, pre_pwm2, pre_pwm1, pre_pwm0, 1, 0, 0]
                        if(update_state):
                            self.state += 1
                            self.pre_pwmout = [0, 0, 0, pre_pwm2, pre_pwm1, pre_pwm0, 1, 0]    
                    case 16:
                        self.pre_pwmout = [0, 0, 0, pre_pwm2, pre_pwm1, pre_pwm0, 1, 0]
                        if(update_state):
                            self.state += 1
                            self.pre_pwmout = [0, 0, 0, 0, pre_pwm2, pre_pwm1, pre_pwm0, 1]
                    case 17:
                        self.pre_pwmout = [0, 0, 0, 0, pre_pwm2, pre_pwm1, pre_pwm0, 1]
                        if(update_state):
                            self.state += 1
                            self.pre_pwmout = [0, 0, 0, 0, 0, pre_pwm2, pre_pwm1, pre_pwm0]
                    case 18:
                        self.pre_pwmout = [0, 0, 0, 0, 0, pre_pwm2, pre_pwm1, pre_pwm0]
                        if(update_state):
                            self.state += 1
                            self.pre_pwmout = [0, 0, 0, 0, 0, 0, pre_pwm2, pre_pwm1]
                    case 19:
                        self.pre_pwmout = [0, 0, 0, 0, 0, 0, pre_pwm2, pre_pwm1]
                        if(update_state):
                            self.state += 1
                            self.pre_pwmout = [0, 0, 0, 0, 0, 0, 0, pre_pwm2]
                    case 20:
                        self.pre_pwmout = [0, 0, 0, 0, 0, 0, 0, pre_pwm2]
                        if(update_state):
                            self.state += 1
                            self.pre_pwmout = [0, 0, 0, 0, 0, 0, 0, 1]   
                    case 21:
                        self.pre_pwmout = [0, 0, 0, 0, 0, 0, 0, 1]                   
                        if(update_state):
                            self.state += 1
                            self.pre_pwmout = [0, 0, 0, 0, 0, 0, 1, pre_pwm0]
                    case 22:
                        self.pre_pwmout = [0, 0, 0, 0, 0, 0, 1, pre_pwm0]
                        if(update_state):
                            self.state += 1
                            self.pre_pwmout = [0, 0, 0, 0, 0, 1, pre_pwm0, pre_pwm1]
                    case 23:
                        self.pre_pwmout = [0, 0, 0, 0, 0, 1, pre_pwm0, pre_pwm1]
                        if(update_state):
                            self.state += 1
                            self.pre_pwmout = [0, 0, 0, 0, 1, pre_pwm0, pre_pwm1, pre_pwm2]
                    case 24:
                        self.pre_pwmout = [0, 0, 0, 0, 1, pre_pwm0, pre_pwm1, pre_pwm2]
                        if(update_state):
                            self.state += 1
                            self.pre_pwmout = [0, 0, 0, 1, pre_pwm0, pre_pwm1, pre_pwm2, 0]
                    case 25:
                        self.pre_pwmout = [0, 0, 0, 1, pre_pwm0, pre_pwm1, pre_pwm2, 0]
                        if(update_state):
                            self.state += 1
                            self.pre_pwmout = [0, 0, 1, pre_pwm0, pre_pwm1, pre_pwm2, 0, 0]
                    case 26:
                        self.pre_pwmout = [0, 0, 1, pre_pwm0, pre_pwm1, pre_pwm2, 0, 0]
                        if(update_state):
                            self.state += 1
                            self.pre_pwmout = [0, 1, pre_pwm0, pre_pwm1, pre_pwm2, 0, 0, 0]
                    case 27:
                        self.pre_pwmout = [0, 1, pre_pwm0, pre_pwm1, pre_pwm2, 0, 0, 0]
                        if(update_state):
                            self.state += 1
                            self.pre_pwmout = [1, pre_pwm0, pre_pwm1, pre_pwm2, 0, 0, 0, 0]
                    case 28:
                        self.pre_pwmout = [1, pre_pwm0, pre_pwm1, pre_pwm2, 0, 0, 0, 0]
                        if(update_state):
                            self.state += 1
                            self.pre_pwmout = [pre_pwm0, pre_pwm1, pre_pwm2, 0, 0, 0, 0, 0]
                    case 29:
                        self.pre_pwmout = [pre_pwm0, pre_pwm1, pre_pwm2, 0, 0, 0, 0, 0]
                        if(update_state):
                            self.state += 1
                            self.pre_pwmout = [pre_pwm1, pre_pwm2, 0, 0, 0, 0, 0, 0]
                    case 30:
                        self.pre_pwmout = [pre_pwm1, pre_pwm2, 0, 0, 0, 0, 0, 0]
                        if(update_state):
                            self.state += 1
                            self.pre_pwmout = [pre_pwm2, 0, 0, 0, 0, 0, 0, 0]
                    case 31:
                        self.pre_pwmout = [pre_pwm2, 0, 0, 0, 0, 0, 0, 0]
                        if(update_state):
                            self.state = 10
                            self.pre_pwmout = [1, 0, 0, 0, 0, 0, 0, 0]
                    case  _:
                        pass
            self.pre_update_state = update_state

            for i in range(8):
                tmp_led = self.pre_pwmout[i] if self.osel != 0 else self.pre_ledout[i]
                tmp_pwm = self.pre_pwmout[i]

                if(self.oinv == 1):
                    tmp_pwm = 1 if tmp_pwm == 0 else 0
                    tmp_led = 1 if tmp_led == 0 else 0

                self.pwmout[i] = tmp_pwm
                self.ledout[i] = tmp_led

        return [self.pwmout, self.ledout]


async def debouncer_checker(db, dut):
    while True:
        await ClockCycles(dut.clk, 1)
        model_out = db.update()
        assert model_out == dut.user_project.i_debouncer.ena_out.value, \
            (f"Debouncer output mismatch: model={model_out}, dut={dut.user_project.i_debouncer.ena_out.value} m_state={db.state} sample={db.sample} counter={db.counter}")

async def kitt_scanner_checker(dut, ks, db):
    while True:
        await ClockCycles(dut.clk, 1)
        db_out = db.update()
        # assert db_out == dut.user_project.i_debouncer.ena_out.value, \
        #     (f"Debouncer output mismatch: model={db_out}, dut={dut.user_project.i_debouncer.ena_out.value} m_state={db.state} sample={db.sample} counter={db.counter}")
        [ks_pwmout, ks_ledout] = ks.update(db_out)

        for i in range(8):          
            assert ks_pwmout[i] == int(dut.uo_out.value[i]), \
                (f"PWM{i} out mismatch: model={ks_pwmout[i]}, dut={dut.uo_out.value[i]} \
                {dut.user_project.i_kitt_scan_core.state.value} {ks.state} {ks_pwmout} {dut.uo_out.value} {ks.counter} {ks.pwm_counter} {dut.user_project.i_kitt_scan_core.pwm_count}")


@cocotb.test()
async def test_project(dut):
    # Reset
    dut._log.info("Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0

    # Set the clock period to 100ns (10 MHz)
    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    disp = info_time(dut)
    cocotb.start_soon(disp)

    await ClockCycles(dut.clk, 1)

    db = debouncer_model(dut, sample_interval=250000) # 25ms at 10MHz
    ks = kitt_scanner_model(dut)

    ks_checker = kitt_scanner_checker(dut, ks, db)
    cocotb.start_soon(ks_checker)

    await ClockCycles(dut.clk, 10, rising=False)
    dut.rst_n.value = 1

    dut._log.info("Test project behavior")

    await ClockCycles(dut.clk, 10)
    dut.ui_in.value =  ((1 << 5) + (1 << 3) + 1)  # Start the scanning
    dut._log.info("Enable")
        
    await ClockCycles(dut.clk, (int)(10 * 10**6 * 1))# Wait for 1 second)
