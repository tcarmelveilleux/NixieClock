; ********************************************************************
; * Nixie Tube Clock firmware v1.10 by Tennessee Carmel-Veilleux     *
; * (C)2003 Tennessee Carmel-Veilleux  <tcv - at - ro.boto.ca>       *
; *                                                                  *
; * Started: ??? (2000)                                              *
; * Working: January 14th 2003                                       *
; * Bug fixes: August 21st 2005                                      *
; *                                                                  *
; * LICENSE: MIT License.                                            *
; * Copyright (C) 2003 Tennessee Carmel-Veilleux <tcv at ro.boto.ca> *
; *                                                                  *
; * Permission is hereby granted, free of charge, to any person      *
; * obtaining a copy of this software and associated documentation   *
; * files (the "Software"), to deal in the Software without          *
; * restriction, including without limitation the rights to use,     *
; * copy, modify, merge, publish, distribute, sublicense, and/or     *
; * sell copies of the Software, and to permit persons to whom the   *
; * Software is furnished to do so, subject to the following         *
; * conditions:                                                      *
; *                                                                  *
; * The above copyright notice and this permission notice shall be   *
; * included in all copies or substantial portions of the Software.  *
; *                                                                  *
; * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,  *
; * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES  *
; * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND         *
; * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT      *
; * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,     *
; * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING     *
; * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR    *
; * OTHER DEALINGS IN THE SOFTWARE.                                  *
; *                                                                  *
; * Tools used: CA65 assembler and LD65 linker on MacOS X 10.2.3.    *
; ********************************************************************

; *** RIOT (6532) Registers
RIOT_DDRA = $81 
RIOT_DDRB = $83 
RIOT_PORTA = $80
RIOT_PORTB = $82

; *** VIA (6522) Registers
VIA_DDRA = $0203
VIA_DDRB = $0202
VIA_PORTA = $020F
VIA_PORTB = $0200
VIA_PCR = $020C 
VIA_ACR = $020B
VIA_IER = $020E

; *** RTC (DS1287) Registers and Constants
RTC_A = $0A 	; RTC control register A
RTC_B = $0B	; RTC control register B
RTC_C = $0C	; RTC control register C
RTC_D = $0D	; RTC control register D

RTCADDR = $0400	; RTC address strobe
RTCDATA = $0401	; RTC data latch

RTC_HOUR = $04	; Hours register
RTC_MIN = $02	; Minutes register
RTC_SEC = $00	; Seconds register
RTC_DOW = $06	; Day of the Week register
RTC_DAY = $07	; Day of the Month register
RTC_MONTH = $08 ; Month register
RTC_YEAR = $09	; Year register
ALARM_HOUR = $05 ; Alarm hour register
ALARM_MIN = $03	; Alarm minute register 
ALARM_SEC = $01 ; Alarm second register

MAGIC1 = $0E	; Magic location 1 ($AA)
MAGIC2 = $0F	; Magic location 2 ($55)

RTC_SET = $83
RTC_NORMAL = $23
RTC_BLURP = $2B

; *** Button states latch
B_SNOOZE = $01	; Snooze Button (0 = ON)
B_ALARM = $02	; Alarm Button (1 = ON)
B_MINS = $04	; Minutes Toggle (0 = ON)
B_HOURS = $08	; Hours Toggle (0 = ON)
B_DOWN = $10	; Down Button (0 = ON)
B_UP = $20	; Up Button (0 = ON)
B_NONE = $00	; *** STATE, not a button

; *** Digits constants
D_RIGHT = VIA_PORTA
D_CENTER = RIOT_PORTA
D_LEFT = RIOT_PORTB

; *** State Machine constants
MAX_BUZZ = 45
MAX_SNOOZE = 5
S_TIME = $00
S_DATE = $01
S_YEAR = $02
S_ALARM = $03
S_SET_MIN = $04
S_SET_HOUR = $05
S_SET_DAY = $06
S_SET_MONTH = $07
S_SET_YEAR = $08
S_SET_DOW = $09
S_SET_A_MIN = $0A
S_SET_A_HOUR = $0B

.zeropage
CurrentState: .res 1	; Current state of the state machine
StateHandler: .res 2	; State routine address for JMP indirect
tmp1: .res 1		; Temporary variable
T_MIN: .res 1		; Holder for minutes
T_SEC: .res 1		; Holder for seconds
T_HOUR: .res 1		; Holder for hours
T_DOW: .res 1		; Holder for day of the week
T_DAY: .res 1		; Holder for day of the month 
T_MONTH: .res 1		; Holder for month
T_YEAR: .res 1		; Holder for year
ButtonState: .res 1	; State of buttons
OLD_AL_MIN: .res 1	; Alarm Minutes save copy
OLD_AL_HOUR: .res 1	; Alarm Hours save copy
SnoozeCount: .res 1	; Snooze count
BuzzCount: .res 1	; Number of alarm buzzes
A_SAVE: .res 1		; Temporary A storage for IRQ restore
X_SAVE: .res 1		; Temporary X storage for IRQ restore
Y_SAVE:	.res 1		; Temporary Y storage for IRQ restore
.code

; *** WriteRTC: This macro will write the 'data' byte at 'address' of the RTC
.macro WriteRTC address, data
    lda #address
    sta RTCADDR
    lda #data
    sta RTCDATA
.endmacro

; *** WriteVarRTC: This macro will write the 'data' variable at 'address' of the RTC
.macro WriteVarRTC address, data
    lda #address
    sta RTCADDR
    lda data
    sta RTCDATA
.endmacro

; *** ReadRTC: This macro will load the accu with the byte at 'address' of RTC
.macro ReadRTC address
    lda #address
    sta RTCADDR
    lda RTCDATA
.endmacro    

; *** CheckButton: This macro will check if 'which' button is pressed. If not,
; it will branch to label 'ifnot'
.macro CheckButton which, ifnot
    lda VIA_PORTB
    and #which
    bne ifnot
.endmacro

.macro CheckButtonNone
    .local loop
    jsr Delay
loop:    
    lda VIA_PORTB	; Read button states
    and #$30		; Keep only UP/DOWN bits
    cmp #$30		; Both buttons up ?
    bne loop		; No... Loop
.endmacro

.code
STATE_TABLE:
.word DisplayTime
.word DisplayDate
.word DisplayYear
.word DisplayAlarm
.word SetMinutes
.word SetHours
.word SetDay
.word SetMonth
.word SetYear
.word SetDOW
.word SetAlMinutes
.word SetAlHours

UP_STATE_TABLE:
.byte S_DATE	; After time: date
.byte S_YEAR	; After date: year
.byte S_ALARM	; After year: alarm
.byte S_TIME	; After alarm: time

DOWN_STATE_TABLE:
.byte S_ALARM	; before time: alarm
.byte S_TIME	; before date: time
.byte S_DATE	; before year: date
.byte S_YEAR	; before alarm: year

RESET: 
    sei             	; Disable interrupts
    cld			; Clear Decimal Mode
    ldx #$7f		; Set top of stack to $7F
    txs
    lda #$ff		; Set RIOT PA, PB and VIA PA for output
    sta RIOT_DDRA
    sta RIOT_DDRB
    sta VIA_DDRA
    lda #$00
    sta VIA_DDRB	; Set VIA PB for input

    jsr CheckClockInit	; Check for clock initialization
    jsr AlarmInit	; Initialize the alarm
    
    lda #S_TIME
    sta CurrentState
    
    lda CurrentState
    jmp RunHandler

; *** RunHandler: This entry point will jump to the state handler in the accum    
RunHandler:
    pha
    asl        ; Multiply state number by two to get byte index in the table
    tax
    lda STATE_TABLE,x    
    sta StateHandler    ; Load and store LSB of handler address
    inx
    lda STATE_TABLE,x    ; Load and store MSB of handler address
    sta StateHandler+1
    pla
    jmp (StateHandler)

; *** Swap: This routine will swap the nibbles of the accumulator 
Swap:
    sta tmp1
    ror tmp1
    ror
    ror tmp1
    ror
    ror tmp1
    ror
    ror tmp1
    ror
    rts

; *** InitRTC: RTC re-initialisation. Sets the time to 00:00:00 on Jan 1 2003
InitRTC:  
	WriteRTC RTC_A,$29	; Turn on the clock for the first time
				; SQW set to 32Hz
	WriteRTC RTC_B,$82	; Put the clock in Set mode, 24H, BCD
	
	; Set the time to 00:00:00
	WriteRTC RTC_SEC,$00
        WriteRTC RTC_MIN,$00
	WriteRTC RTC_HOUR,$00

	; Set the date to Wednesday January 1st 2003 
	WriteRTC RTC_DAY,$01
        WriteRTC RTC_MONTH,$01
	WriteRTC RTC_YEAR,$03
	WriteRTC RTC_DOW,$04	; 01/01/2003 was a wednesday
	
	; Set the alarm to 12:00:00
	WriteRTC ALARM_SEC,$00
        WriteRTC ALARM_MIN,$00
	WriteRTC ALARM_HOUR,$12
	
	WriteRTC RTC_B,RTC_NORMAL	; Back to Normal Operation, 24H, DSE, BCD
	
	; Set the Magic locations to "initialized"
	WriteRTC MAGIC1,$AA
	WriteRTC MAGIC2,$55
	RTS
	
; *** GetTime: Get the time from the RTC.
GetTime: 	
    ReadRTC RTC_SEC	
    sta T_SEC		; Read and store seconds	

    ReadRTC RTC_MIN
    sta T_MIN		; Read and store minutes
                                            
    ReadRTC RTC_HOUR
    sta T_HOUR		; Read and store hours

    rts
	
; *** GetAlarm: Get the alarm time from the RTC.
GetAlarm: 	
    ReadRTC ALARM_SEC	
    sta T_SEC		; Read and store seconds	

    ReadRTC ALARM_MIN
    sta T_MIN		; Read and store minutes
                                            
    ReadRTC ALARM_HOUR
    sta T_HOUR		; Read and store hours

    rts

; *** GetDate: Get the date from the RTC.
GetDate: 
    ReadRTC RTC_DAY
    sta T_DAY		; Read and store minutes
                                            
    ReadRTC RTC_MONTH
    sta T_MONTH		; Read and store hours
	
    rts

; *** GetYear: Get the year from the RTC.	
GetYear:
    ReadRTC RTC_YEAR
    sta T_YEAR	; Read and store the year
	
    ReadRTC RTC_DOW
    sta T_DOW	; Read and store the Day Of the Week
	
    rts
	
; *** CheckClockInit: This routine will check to see that the clock has been
; initialized at least once. If not, or if a special combo of keys is pressed,
; a re-initialisation will occur
CheckClockInit:
    ReadRTC MAGIC1
    cmp #$AA
    bne CheckClockInit_Reset
    
    ReadRTC MAGIC2
    cmp #$55
    bne CheckClockInit_Reset
    
    ; Check for magic button combo: all switches down
    lda VIA_PORTB	; Read button states
    and #$3F		; Mask 2 MSb's
    cmp #$28		; Compare with value of all down
    beq	CheckClockInit_Reset
    
    rts			; *** FALLTHROUGH: return if everything is all right
CheckClockInit_Reset:
    jsr InitRTC		; Reinit the RTC
    rts			; Return from function
    
; *** ModeCheck: This routine will handle the mode change for UP/DOWN
ModeCheck:     
; Check for UP button
    CheckButton B_UP,ModeCheckDown
    pla				; Change of state detected, discard JSR's PC
    pla
    lda CurrentState		; Use current state as index
    tax
    lda UP_STATE_TABLE,x	; Get NEXT state UP
    sta CurrentState		; Change state
    jmp RunHandler
    
; Check for DOWN button    
ModeCheckDown:    
    CheckButton B_DOWN,ModeCheckDone
    pla				; Change of state detected, discard JSR's PC
    pla
    lda CurrentState		; Use current state as index
    tax  
    lda DOWN_STATE_TABLE,X	; Get NEXT state DOWN
    sta CurrentState		; Change state
    jmp RunHandler
    
ModeCheckDone:
    rts

; *** AlarmCheck: This routine will check to see if alarm is being turned off
AlarmCheck:
    lda VIA_PORTB		; Check to see if Alarm is turned off
    and #$02
    bne AlarmCheckDone		; If not, just return
    lda SnoozeCount		; If so, check if alarm was in progress
    beq AlarmCheckDone		; If not, just return
    jsr AlarmReset		; If alarm was in progress, reset it
AlarmCheckDone:
    rts    
    
; *** TimeSetCheck: This routine will handle setting mode change
TimeSetCheck:     
; Check for UP button
    CheckButton B_HOURS,TimeSetCheckDown
    pla				; Change of state detected, discard JSR's PC
    pla
    lda #S_SET_HOUR		; UP = set hours
    sta CurrentState		; Change state
    jmp RunHandler
    
; Check for DOWN button    
TimeSetCheckDown:    
    CheckButton B_MINS,TimeSetCheckDone
    pla				; Change of state detected, discard JSR's PC
    pla
    lda #S_SET_MIN		; DOWN = set minutes
    sta CurrentState		; Change state
    jmp RunHandler
    
TimeSetCheckDone:
    rts

; *** AlarmSetCheck: This routine will handle setting mode change
AlarmSetCheck:     
; Check for UP button
    CheckButton B_HOURS,AlarmSetCheckDown
    lda SnoozeCount		; Check for SnoozeCount == 0
    beq AlarmSetCheckNoClear	; If so, don't reset the alarm
    jsr AlarmReset		; If not, alarm is in progress, reset it
AlarmSetCheckNoClear:
    pla				; Change of state detected, discard JSR's PC
    pla
    lda #S_SET_A_HOUR		; UP = set alarm hours
    sta CurrentState		; Change state
    jmp RunHandler
    
; Check for DOWN button    
AlarmSetCheckDown:    
    CheckButton B_MINS,AlarmSetCheckDone
    pla				; Change of state detected, discard JSR's PC
    pla
    lda #S_SET_A_MIN		; DOWN = set alarm minutes
    sta CurrentState		; Change state
    jmp RunHandler
    
AlarmSetCheckDone:
    rts    

; *** DateSetCheck: This routine will handle setting mode change
DateSetCheck:     
; Check for UP button
    CheckButton B_HOURS,DateSetCheckDown
    pla				; Change of state detected, discard JSR's PC
    pla
    lda #S_SET_MONTH		; UP = set month
    sta CurrentState		; Change state
    jmp RunHandler
    
; Check for DOWN button    
DateSetCheckDown:    
    CheckButton B_MINS,DateSetCheckDone
    pla				; Change of state detected, discard JSR's PC
    pla
    lda #S_SET_DAY		; DOWN = set day
    sta CurrentState		; Change state
    jmp RunHandler
    
DateSetCheckDone:
    rts    
    
; *** YearSetCheck: This routine will handle setting mode change
YearSetCheck:     
; Check for UP button
    CheckButton B_HOURS,YearSetCheckDown
    pla				; Change of state detected, discard JSR's PC
    pla
    lda #S_SET_DOW		; UP = set day of the week
    sta CurrentState		; Change state
    jmp RunHandler
    
; Check for DOWN button    
YearSetCheckDown:    
    CheckButton B_MINS,YearSetCheckDone
    pla				; Change of state detected, discard JSR's PC
    pla
    lda #S_SET_YEAR		; DOWN = set year
    sta CurrentState		; Change state
    jmp RunHandler
    
YearSetCheckDone:
    rts
    
; *** DisplayTime: Handler to display the time
DisplayTime:      
    cli			; Enable the interrupts while displaying
    CheckButtonNone	; After change of state, wait for button release
DisplayTimeLoop:    
    jsr GetTime		; Get time
    
    lda T_SEC		; Show seconds on the right
    jsr Swap
    sta D_RIGHT

    lda T_MIN		; Show minutes in the middle
    jsr Swap
    sta D_CENTER

    lda T_HOUR		; Show hours on the left
    jsr Swap
    sta D_LEFT
    
    jsr AlarmCheck	; Check for alarm set/reset
    jsr ModeCheck	; Check for mode change
    jsr TimeSetCheck
    jmp DisplayTimeLoop
    
; *** DisplayDate: Handler to display the date
DisplayDate:      
    cli			; Enable the interrupts while displaying
    CheckButtonNone	; After change of state, wait for button release
DisplayDateLoop:    
    jsr GetDate		; Get date
    
    lda T_DAY		; Show day on the right
    jsr Swap
    sta D_RIGHT

    lda #$FF		; Show nothing in center
    sta D_CENTER

    lda T_MONTH		; Show month on the left
    jsr Swap
    sta D_LEFT
    
    jsr AlarmCheck	; Check for alarm set/reset
    jsr ModeCheck	; Check for mode change
    jsr DateSetCheck	; Check for setting of date
    jmp DisplayDateLoop
    
; *** DisplayYear: Handler to display the year
DisplayYear:      
    cli			; Enable the interrupts while displaying
    CheckButtonNone	; After change of state, wait for button release
DisplayYearLoop:    
    jsr GetYear		; Get Year
    
    lda T_YEAR		; Show year on the right
    jsr Swap
    sta D_RIGHT

    lda #$20		; Show "20" in center
    jsr Swap
    sta D_CENTER

    lda #$FF		; Show nothing on the left
    sta D_LEFT
     
    jsr AlarmCheck	; Check for alarm set/reset
    jsr ModeCheck	; Check for mode change
    jsr YearSetCheck	; Check for setting of year/DOW
    jmp DisplayYearLoop

; *** DisplayAlarm: Handler to display the alarm time
DisplayAlarm:      
    cli			; Enable the interrupts while displaying
    CheckButtonNone	; After change of state, wait for button release
DisplayAlarmLoop:    
    lda SnoozeCount
    bne DisplayAlarmOld	; Display old value if in snooze (SnoozeCount != 0)
    
    jsr GetAlarm	; Get Alarm time
    
    lda #$FF		; Show nothing on the right
    sta D_RIGHT

    lda T_MIN		; Show minutes in the middle
    jsr Swap
    sta D_CENTER

    lda T_HOUR		; Show hours on the left
    jsr Swap
    sta D_LEFT
    jmp DisplayAlarmDoLoop

DisplayAlarmOld:    
    lda #$FF		; Show nothing on the right
    sta D_RIGHT

    lda OLD_AL_MIN	; Show old minutes in the middle
    jsr Swap
    sta D_CENTER

    lda OLD_AL_HOUR	; Show old hours on the left
    jsr Swap
    sta D_LEFT
    
DisplayAlarmDoLoop:    
    jsr AlarmCheck	; Check for alarm set/reset
    jsr ModeCheck	; Check for mode change
    jsr AlarmSetCheck	; Check for setting of Alarm
    jmp DisplayAlarmLoop

;*** SetMinutes: This routine handles the setting of minutes
SetMinutes:
    sei			; Disable the interrupts while setting
    CheckButtonNone
    jsr GetTime		; Get time
    
    lda #$0F		; Show seconds as _0 on the right
    sta D_RIGHT

    lda T_MIN		; Show minutes in the middle
    jsr Swap
    sta D_CENTER

    lda T_HOUR		; Show hours on the left
    jsr Swap
    sta D_LEFT

    WriteRTC RTC_B,RTC_SET		; Set the clock to SET mode, BCD, 24H, DSE
    
SetMinutesLoop:     
    CheckButton B_UP, SetMinutesCheckDown	; Check for UP button
    jsr LongDelay				; Debounce
    CheckButton B_UP, SetMinutesCheckDown
    sed
    clc
    lda T_MIN
    adc #$01						
    sta T_MIN		; Increase in decimal
    cld
    cmp #$60		; Check for overflow of 59->60
    bne SetMinutesShowMinutes
    lda #$00		; If overflow, clear to 00
    sta T_MIN
    jmp SetMinutesShowMinutes
SetMinutesCheckDown:
    CheckButton B_DOWN, SetMinutesCheckReturn	; Check for DOWN button
    jsr LongDelay				; Debounce
    CheckButton B_DOWN, SetMinutesCheckReturn
    sed
    clc
    lda T_MIN
    sec
    sbc #$01
    sta T_MIN		; Decrease in decimal
    cld	
    lda T_MIN
    cmp #$99		; Check for underflow 00->99
    bne SetMinutesShowMinutes
    lda #$59		; If underflow, return to 59 instead of 99	
    sta T_MIN	
SetMinutesShowMinutes:    
    jsr Swap		; Show updated minutes
    sta D_CENTER
    ReadRTC RTC_HOUR	; Show updating hours
    jsr Swap
    sta D_LEFT

SetMinutesCheckReturn:
    lda VIA_PORTB	; Check for both mode buttons up
    and #$0C
    cmp #$0C
    bne SetMinutesCheckDone	; If buttons still down, go to loop
    WriteVarRTC RTC_MIN, T_MIN	; Write time back to RTC
    WriteRTC RTC_SEC,$00
    WriteRTC RTC_B,RTC_NORMAL		; Return RTC to normal mode
    lda #S_TIME			
    sta CurrentState
    jmp RunHandler		; Return to time display state

SetMinutesCheckDone:
    ReadRTC RTC_HOUR	; Show updating hours
    jsr Swap
    sta D_LEFT
    jmp SetMinutesLoop    

;*** SetHours: This routine handles the setting of hours
SetHours:
    sei			; Disable the interrupts while setting
    CheckButtonNone
    jsr GetTime		; Get time
    
    lda #$F0		; Show seconds as 0_ on the right
    sta D_RIGHT

    lda T_MIN		; Show minutes in the middle
    jsr Swap
    sta D_CENTER

    lda T_HOUR		; Show hours on the left
    jsr Swap
    sta D_LEFT

    WriteRTC RTC_B,RTC_SET		; Set the clock to SET mode, BCD, 24H, DSE
    
SetHoursLoop:     
    CheckButton B_UP, SetHoursCheckDown	; Check for UP button
    jsr LongDelay			; Debounce
    CheckButton B_UP, SetHoursCheckDown
    sed
    clc
    lda T_HOUR
    adc #$01						
    sta T_HOUR		; Increase in decimal
    cld
    cmp #$24		; Check for overflow of 23->00
    bne SetHoursShowHours
    lda #$00		; If overflow, clear to 00
    sta T_HOUR
    jmp SetHoursShowHours
SetHoursCheckDown:
    CheckButton B_DOWN, SetHoursCheckReturn	; Check for DOWN button
    jsr LongDelay				; Debounce
    CheckButton B_DOWN, SetHoursCheckReturn
    sed
    lda T_HOUR
    sec
    sbc #$01
    sta T_HOUR		; Decrease in decimal
    cld	
    lda T_HOUR
    cmp #$99		; Check for underflow 00->99
    bne SetHoursShowHours
    lda #$23		; If underflow, return to 23 instead of 99	
    sta T_HOUR	
SetHoursShowHours:    
    jsr Swap		; Show updated hours
    sta D_LEFT
    ReadRTC RTC_MIN	; Show updating minutes
    jsr Swap
    sta D_CENTER
SetHoursCheckReturn:
    lda VIA_PORTB	; Check for both mode buttons up
    and #$0C
    cmp #$0C
    bne SetHoursCheckDone	; If buttons still down, go to loop
    WriteVarRTC RTC_HOUR, T_HOUR	; Write time back to RTC
    WriteRTC RTC_SEC,$00
    WriteRTC RTC_B,RTC_NORMAL		; Return RTC to normal mode
    lda #S_TIME			
    sta CurrentState
    jmp RunHandler		; Return to time display state

SetHoursCheckDone:
    ReadRTC RTC_MIN	; Show updating minutes
    jsr Swap
    sta D_CENTER
    jmp SetHoursLoop    

;*** SetAlMinutes: This routine handles the setting of alarm minutes
SetAlMinutes:
    sei			; Disable the interrupts while setting
    CheckButtonNone
    jsr GetAlarm	; Get alarm time
    
    lda #$0F		; Show "_0" on the right
    sta D_RIGHT

    lda T_MIN		; Show minutes in the middle
    jsr Swap
    sta D_CENTER

    lda T_HOUR		; Show hours on the left
    jsr Swap
    sta D_LEFT

    WriteRTC RTC_B,RTC_SET		; Set the clock to SET mode, BCD, 24H, DSE
    
SetAlMinutesLoop:     
    CheckButton B_UP, SetAlMinutesCheckDown	; Check for UP button
    jsr LongDelay				; Debounce
    CheckButton B_UP, SetAlMinutesCheckDown
    sed
    clc
    lda T_MIN
    adc #$01						
    sta T_MIN		; Increase in decimal
    cld
    cmp #$60		; Check for overflow of 59->60
    bne SetAlMinutesShowAlMinutes
    lda #$00		; If overflow, clear to 00
    sta T_MIN
    jmp SetAlMinutesShowAlMinutes
SetAlMinutesCheckDown:
    CheckButton B_DOWN, SetAlMinutesCheckReturn	; Check for DOWN button
    jsr LongDelay				; Debounce
    CheckButton B_DOWN, SetAlMinutesCheckReturn
    sed
    clc
    lda T_MIN
    sec
    sbc #$01
    sta T_MIN		; Decrease in decimal
    cld	
    lda T_MIN
    cmp #$99		; Check for underflow 00->99
    bne SetAlMinutesShowAlMinutes
    lda #$59		; If underflow, return to 59 instead of 99	
    sta T_MIN	
SetAlMinutesShowAlMinutes:    
    jsr Swap		; Show updated minutes
    sta D_CENTER

SetAlMinutesCheckReturn:
    lda VIA_PORTB	; Check for both mode buttons up
    and #$0C
    cmp #$0C
    bne SetAlMinutesCheckDone	; If buttons still down, go to loop
    WriteVarRTC ALARM_MIN, T_MIN	; Write time back to RTC
    WriteRTC ALARM_SEC,$00
    WriteRTC RTC_B,RTC_NORMAL		; Return RTC to normal mode
    lda #S_ALARM			
    sta CurrentState
    jmp RunHandler		; Return to time display state

SetAlMinutesCheckDone:
    jmp SetAlMinutesLoop    

;*** SetAlHours: This routine handles the setting of alarm hours
SetAlHours:
    sei			; Disable the interrupts while setting
    CheckButtonNone
    jsr GetAlarm	; Get alarm
    
    lda #$F0		; Show "0_" on the right
    sta D_RIGHT

    lda T_MIN		; Show minutes in the middle
    jsr Swap
    sta D_CENTER

    lda T_HOUR		; Show hours on the left
    jsr Swap
    sta D_LEFT

    WriteRTC RTC_B,RTC_SET		; Set the clock to SET mode, BCD, 24H, DSE
    
SetAlHoursLoop:     
    CheckButton B_UP, SetAlHoursCheckDown	; Check for UP button
    jsr LongDelay			; Debounce
    CheckButton B_UP, SetAlHoursCheckDown
    sed
    clc
    lda T_HOUR
    adc #$01						
    sta T_HOUR		; Increase in decimal
    cld
    cmp #$24		; Check for overflow of 23->24
    bne SetAlHoursShowAlHours
    lda #$00		; If overflow, clear to 00
    sta T_HOUR
    jmp SetAlHoursShowAlHours
SetAlHoursCheckDown:
    CheckButton B_DOWN, SetAlHoursCheckReturn	; Check for DOWN button
    jsr LongDelay				; Debounce
    CheckButton B_DOWN, SetAlHoursCheckReturn
    sed
    lda T_HOUR
    sec
    sbc #$01
    sta T_HOUR		; Decrease in decimal
    cld	
    lda T_HOUR
    cmp #$99		; Check for underflow 00->99
    bne SetAlHoursShowAlHours
    lda #$23		; If underflow, return to 23 instead of 99	
    sta T_HOUR	
SetAlHoursShowAlHours:    
    jsr Swap		; Show updated hours
    sta D_LEFT
    
SetAlHoursCheckReturn:
    lda VIA_PORTB	; Check for both mode buttons up
    and #$0C
    cmp #$0C
    bne SetAlHoursCheckDone	; If buttons still down, go to loop
    WriteVarRTC ALARM_HOUR, T_HOUR	; Write time back to RTC
    WriteRTC ALARM_SEC,$00
    WriteRTC RTC_B,RTC_NORMAL		; Return RTC to normal mode
    lda #S_ALARM			
    sta CurrentState
    jmp RunHandler		; Return to time display state

SetAlHoursCheckDone:
    jmp SetAlHoursLoop    

;*** SetDay: This routine handles the setting of the day
;=== BE CAREFUL: No check to see if day is valid ! (ie: 31 in February)
SetDay:
    sei			; Disable the interrupts while setting
    CheckButtonNone
    jsr GetDate		; Get date
    
    lda T_DAY		; Show day on the right
    jsr Swap
    sta D_RIGHT

    lda #$88		; Show "88" in the middle
    sta D_CENTER

    lda T_MONTH		; Show month on the left
    jsr Swap
    sta D_LEFT

    WriteRTC RTC_B,RTC_SET		; Set the clock to SET mode, BCD, 24H, DSE
    
SetDayLoop:     
    CheckButton B_UP, SetDayCheckDown	; Check for UP button
    jsr LongDelay				; Debounce
    CheckButton B_UP, SetDayCheckDown
    sed
    clc
    lda T_DAY
    adc #$01						
    sta T_DAY		; Increase in decimal
    cld
    cmp #$32		; Check for overflow of 31->32
    bne SetDayShowDay
    lda #$01		; If overflow, clear to 01
    sta T_DAY
    jmp SetDayShowDay
SetDayCheckDown:
    CheckButton B_DOWN, SetDayCheckReturn	; Check for DOWN button
    jsr LongDelay				; Debounce
    CheckButton B_DOWN, SetDayCheckReturn
    sed
    clc
    lda T_DAY
    sec
    sbc #$01
    sta T_DAY		; Decrease in decimal
    cld	
    lda T_DAY
    cmp #$00		; Check for underflow 01->00
    bne SetDayShowDay
    lda #$31		; If underflow, return to 31 instead of 00	
    sta T_DAY	
SetDayShowDay:    
    jsr Swap		; Show updated day
    sta D_RIGHT
   
SetDayCheckReturn:
    lda VIA_PORTB	; Check for both mode buttons up
    and #$0C
    cmp #$0C
    bne SetDayCheckDone	; If buttons still down, go to loop
    WriteVarRTC RTC_DAY, T_DAY	; Write time back to RTC
    WriteRTC RTC_B,RTC_NORMAL		; Return RTC to normal mode
    lda #S_DATE			
    sta CurrentState
    jmp RunHandler		; Return to time display state

SetDayCheckDone:
    jmp SetDayLoop    

;*** SetMonth: This routine handles the setting of the month
SetMonth:
    sei			; Disable the interrupts while setting
    CheckButtonNone
    jsr GetDate		; Get date
    
    lda T_DAY		; Show day on the right
    jsr Swap
    sta D_RIGHT

    lda #$88		; Show "88" in the middle
    sta D_CENTER

    lda T_MONTH		; Show month on the left
    jsr Swap
    sta D_LEFT

    WriteRTC RTC_B,RTC_SET		; Set the clock to SET mode, BCD, 24H, DSE
    
SetMonthLoop:     
    CheckButton B_UP, SetMonthCheckDown	; Check for UP button
    jsr LongDelay			; Debounce
    CheckButton B_UP, SetMonthCheckDown
    sed
    clc
    lda T_MONTH
    adc #$01						
    sta T_MONTH		; Increase in decimal
    cld
    cmp #$13		; Check for overflow of 12->13
    bne SetMonthShowMonth
    lda #$01		; If overflow, clear to 01
    sta T_MONTH
    jmp SetMonthShowMonth
SetMonthCheckDown:
    CheckButton B_DOWN, SetMonthCheckReturn	; Check for DOWN button
    jsr LongDelay				; Debounce
    CheckButton B_DOWN, SetMonthCheckReturn
    sed
    lda T_MONTH
    sec
    sbc #$01
    sta T_MONTH		; Decrease in decimal
    cld	
    lda T_MONTH
    cmp #$00		; Check for underflow 01->00
    bne SetMonthShowMonth
    lda #$12		; If underflow, return to 12 instead of 00	
    sta T_MONTH	
SetMonthShowMonth:    
    jsr Swap		; Show updated month
    sta D_LEFT
SetMonthCheckReturn:
    lda VIA_PORTB	; Check for both mode buttons up
    and #$0C
    cmp #$0C
    bne SetMonthCheckDone	; If buttons still down, go to loop
    WriteVarRTC RTC_MONTH, T_MONTH	; Write time back to RTC
    WriteRTC RTC_B,RTC_NORMAL		; Return RTC to normal mode
    lda #S_DATE			
    sta CurrentState
    jmp RunHandler		; Return to time display state

SetMonthCheckDone:
    jmp SetMonthLoop    
    
;*** SetYear: This routine handles the setting of the year
SetYear:
    sei			; Disable the interrupts while setting
    CheckButtonNone
    jsr GetYear		; Get year
    
    lda T_YEAR		; Show year on the right
    jsr Swap
    sta D_RIGHT

    lda #$02		; Show "20" in the middle
    sta D_CENTER

    lda #$F0		; Show "0 " on the left
    sta D_LEFT

    WriteRTC RTC_B,RTC_SET		; Set the clock to SET mode, BCD, 24H, DSE
    
SetYearLoop:     
    CheckButton B_UP, SetYearCheckDown	; Check for UP button
    jsr LongDelay				; Debounce
    CheckButton B_UP, SetYearCheckDown
    sed
    clc
    lda T_YEAR
    adc #$01						
    sta T_YEAR		; Increase in decimal
    cld
    cmp #$00		; Check for overflow of 99->00
    bne SetYearShowYear
    lda #$03		; If overflow, set to 03 instead of 00
    sta T_YEAR
    jmp SetYearShowYear
SetYearCheckDown:
    CheckButton B_DOWN, SetYearCheckReturn	; Check for DOWN button
    jsr LongDelay				; Debounce
    CheckButton B_DOWN, SetYearCheckReturn
    sed
    clc
    lda T_YEAR
    sec
    sbc #$01
    sta T_YEAR		; Decrease in decimal
    cld	
    lda T_YEAR
    cmp #$02		; Check for underflow 03->02
    bne SetYearShowYear
    lda #$99		; If underflow, return to 99 instead of 02	
    sta T_YEAR	
SetYearShowYear:    
    jsr Swap		; Show updated year
    sta D_RIGHT
   
SetYearCheckReturn:
    lda VIA_PORTB	; Check for both mode buttons up
    and #$0C
    cmp #$0C
    bne SetYearCheckDone	; If buttons still down, go to loop
    WriteVarRTC RTC_YEAR, T_YEAR	; Write time back to RTC
    WriteRTC RTC_B,RTC_NORMAL		; Return RTC to normal mode
    lda #S_YEAR			
    sta CurrentState
    jmp RunHandler		; Return to time display state

SetYearCheckDone:
    jmp SetYearLoop    

;*** SetDOW: This routine handles the setting of the day of the week
SetDOW:
    sei			; Disable the interrupts while setting
    CheckButtonNone
    jsr GetYear		; Get year (and DOW)
    
    lda #$0F		; Show " 0" on the right
    sta D_RIGHT

    lda #$FF		; Show nothing in the middle
    sta D_CENTER

    lda T_DOW		; Show day of the week on the left
    jsr Swap
    sta D_LEFT

    WriteRTC RTC_B,RTC_SET		; Set the clock to SET mode, BCD, 24H, DSE
    
SetDOWLoop:     
    CheckButton B_UP, SetDOWCheckDown	; Check for UP button
    jsr LongDelay			; Debounce
    CheckButton B_UP, SetDOWCheckDown
    sed
    clc
    lda T_DOW
    adc #$01						
    sta T_DOW		; Increase in decimal
    cld
    cmp #$08		; Check for overflow of 07->08
    bne SetDOWShowDOW
    lda #$01		; If overflow, clear to 01
    sta T_DOW
    jmp SetDOWShowDOW
SetDOWCheckDown:
    CheckButton B_DOWN, SetDOWCheckReturn	; Check for DOWN button
    jsr LongDelay				; Debounce
    CheckButton B_DOWN, SetDOWCheckReturn
    sed
    lda T_DOW
    sec
    sbc #$01
    sta T_DOW		; Decrease in decimal
    cld	
    lda T_DOW
    cmp #$00		; Check for underflow 01->00
    bne SetDOWShowDOW
    lda #$07		; If underflow, return to 7 instead of 00	
    sta T_DOW	
SetDOWShowDOW:    
    jsr Swap		; Show updated DOW
    sta D_LEFT
SetDOWCheckReturn:
    lda VIA_PORTB	; Check for both mode buttons up
    and #$0C
    cmp #$0C
    bne SetDOWCheckDone	; If buttons still down, go to loop
    WriteVarRTC RTC_DOW, T_DOW	; Write time back to RTC
    WriteRTC RTC_B,RTC_NORMAL		; Return RTC to normal mode
    lda #S_YEAR			
    sta CurrentState
    jmp RunHandler		; Return to time display state

SetDOWCheckDone:
    jmp SetDOWLoop    

; *** AddTenMinutes: This routine will add 10 minutes to the alarm
AddTenMinutes:
    jsr GetAlarm	; Get alarm time in TI_MIN/TI_HOUR
    sed
    clc			; Set decimal mode and clear carry for addition
    lda T_MIN		; Load alarm minutes
    adc #$10
    cmp #$59		; Check if minutes are < 59 after adding 10
    beq AddTenMinutesHours	; If so, just skip the hours carry
    bmi AddTenMinutesHours
    and #$0F		; If not, keep only low minutes (from 61->01)
    sec			; Set carry for adding an hour
AddTenMinutesHours:
    sta T_MIN		; Store updated minutes    
    lda T_HOUR		; Load alarm hours
    adc #$00		; Add the carry to the hours
    cmp #$24		; If hours reach 24, roll-over to 00
    bne AddTenMinutesUpdate	; If not, just update the Alarm
    lda #00		; Roll-over
AddTenMinutesUpdate:	; Update the alarm time in the RTC
    sta T_HOUR		; Store updated minutes (dual roll-over) 
    WriteVarRTC ALARM_MIN,T_MIN
    WriteVarRTC ALARM_HOUR,T_HOUR
    cld			; Return to normal arithmetic !
    rts
    
; *** AlarmInit: Called to initialize the alarm and turn on the IRQ
AlarmInit:
    lda #$00			
    sta SnoozeCount		; Clear snooze count
    ReadRTC RTC_C		; Clear interrupt flags on the DS1287
    WriteRTC RTC_B,RTC_NORMAL	; Enable Interrupts
    cli				; Enable 6502 interrupts
    rts

; *** AlarmHandler: This routine sounds the alarm and checks all alarm statuses
AlarmHandler:
    lda SnoozeCount		; Get SnoozeCount
    bne AlarmHandlerBuzz	; Skip saving if not in first alarm run
    
    ReadRTC ALARM_MIN		; Save the alarm minutes
    sta OLD_AL_MIN		
    
    ReadRTC ALARM_HOUR		; Save the alarm hours
    sta OLD_AL_HOUR
AlarmHandlerBuzz:
    lda #$00			; Clear buzz count
    sta BuzzCount    
AlarmHandlerBuzzLoop:    
    lda SnoozeCount
    asl
    asl
    asl
    asl
    ora SnoozeCount	; Fill the accum with a double digit copy of SnoozeCount
    sta D_LEFT		; And fill the screen with that number
    sta D_CENTER
    sta D_RIGHT
    
    WriteRTC RTC_B,RTC_BLURP	; Start the buzzer
    jsr AlarmDelay	; Delay a bit
    jsr AlarmDelay	; BUZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ
    jsr AlarmDelay
    WriteRTC RTC_B,RTC_NORMAL	; Stop the buzzer
    
    jsr GetTime		; Display the time
    lda T_SEC		; Show seconds on the right
    jsr Swap
    sta D_RIGHT
    lda T_MIN		; Show minutes in the middle
    jsr Swap
    sta D_CENTER
    lda T_HOUR		; Show hours on the left
    jsr Swap
    sta D_LEFT
    
    jsr AlarmDelay	; Delay to show the time while it is silenced
    jsr AlarmDelay

AlarmHandlerOFFCheck:    
    lda VIA_PORTB	; Read button states
    and #$02		; Check for Alarm set
    bne AlarmHandlerBuzzCheck	; If still Set, go check for end of buzzing
    
    jsr AlarmReset	; If not set, reset alarm
    jmp IRQ_DONE	; *** DONE for alarm handler

AlarmHandlerBuzzCheck:    
    inc BuzzCount	; Increase BuzzCount
    lda BuzzCount
    cmp #MAX_BUZZ	; Compare it against the maximum number of buzzes 
    bne AlarmHandlerSnoozeCheck	; If not reached, check for snooze
    
    jsr AlarmReset	; If maximum reached, stop the alarm, we're not home :)
    jmp IRQ_DONE	; *** DONE for alarm handler
    
AlarmHandlerSnoozeCheck:
    CheckButton B_SNOOZE,AlarmHandlerDoLoop	; Check for snooze button
    inc SnoozeCount	; If pressed, increase snooze count
    jsr AddTenMinutes	; Add 10 minutes to alarm, then wait for next IRQ
    jmp IRQ_DONE	; *** Done for alarm handler
    
AlarmHandlerDoLoop:
    jmp AlarmHandlerBuzzLoop    ; If not done, loop
    
; *** AlarmReset: This routine sets everything back to normal operation    
AlarmReset:
    WriteRTC RTC_B,RTC_SET		; Set RTC mode to SET
    WriteVarRTC ALARM_MIN,OLD_AL_MIN	; Restore alarm minutes
    WriteVarRTC ALARM_HOUR,OLD_AL_HOUR	; Restore alarm hours
    WriteRTC RTC_B,RTC_NORMAL		; Set RTC mode to NORMAL
    lda #$00
    sta SnoozeCount			; Reset SnoozeCount
    rts        
	    
; *** IRQ: This is the main IRQ handler    
IRQ:
    stx X_SAVE		; Save registers
    sty Y_SAVE
    sta A_SAVE
    lda VIA_PORTB	; Read button states
    and #$02		; Check for Alarm set
    beq IRQ_DONE	; If alarm not set
    lda SnoozeCount	
    cmp #MAX_SNOOZE	; Check to see of SnoozeCount is at MAX_SNOOZE
    beq IRQ_OVER	; If so, stop alarm and reset it
    jmp AlarmHandler	; If not, do the alarm routine
			
IRQ_OVER:
    jsr AlarmReset	; Reset Alarm after SnoozeCount > MAX_SNOOZE
IRQ_DONE:
    ReadRTC RTC_C	; Clear interrupt flags
    ldx X_SAVE		; Restore registers
    ldy Y_SAVE
    lda A_SAVE
    rti
    
    
; *** Delay: Small delay for reasonnable debounce    
Delay:
    ldx #$20
    ldy #$10 ; $20
    jmp WaitLoop

; *** AlarmDelay: Long delay for alarm beeping    
AlarmDelay:
    ldx #$20
    ldy #$30
    jmp WaitLoop
    
; *** LongDelay: Medium delay for switch repeat
LongDelay:
    ldx #$20
    ldy #$1A ; $30

WaitLoop: 
    dex
    nop
    nop
    nop
    nop
    nop
    nop
    bne WaitLoop
WaitLoop2:
    dey
    nop
    nop
    nop
    bne WaitLoop
    rts
    
NMI: rti

.segment "VECTORS"
 .word NMI
 .word RESET
 .word IRQ
