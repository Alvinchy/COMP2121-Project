.include "m2560def.inc"

//Define Constants
	
	.equ NUMTOASCII		= 48 //Add this value to a number to convert it to ASCII

	//Keypad related
	.equ INITCOLMASK 	= 0xEF
	.equ INITROWMASK 	= 0x01
	.equ KEYRESETCOUNT	= 0x0D //Count down from this before next key may be read

	//LCD Commands
	.equ CLEARLCD		= 0b00000001 //Clear display and reset cursor
	.equ ROW2LCD		= 0b11000000 //Move cursor to beginning of row 2
	.equ CURSORL		= 0b00010000 //Shift cursor to the left
	.equ CURSORR		= 0b00010100 //Shift cursor to the right

	//Encoding of modes
	.equ STARTMODE		= 0b00000000 //Start screen
	.equ STARTCDMODE	= 0b00000001 //Start screen with countdown
	.equ RESETPOTMODE	= 0b00000010 //Reset potentiometer screen
	.equ FINDPOTMODE	= 0b00000011 //Find potentiometer position screen
	.equ FINDCODEMODE	= 0b00000100 //Find code screen
	.equ ENTERCODEMODE	= 0b00000101 //Enter code screen
	.equ WINMODE		= 0b00000110 //Game complete screen
	.equ LOSEMODE		= 0b00000111 //Timeout screen

	//Number of overflows for times with prescaler 256
	.equ MS1000			= 244
	.equ MS500			= 122
	.equ MS250			= 61

.DSEG
	Code: 			.BYTE 3 //Correct code
	PotTarget: 		.BYTE 1 //Potentiometer target
	PotValue:		.BYTE 1 //Potentiometer read
	PotCorrect:		.BYTE 1 //Flag indicating if the potentiometer position is correct
	PotRoundClear:	.BYTE 1 //Flag indicating if the potentiometer round has been successfully cleared
	RoundNum: 		.BYTE 1 //Number of rounds played
	CDTime:			.BYTE 1	//Countdown time
	CDEnable:		.BYTE 1 //Flag indicating if countdown timer is active
	Mode:			.BYTE 1	//Current screen
	PBDisable:		.BYTE 1	//Disable push buttons (flag)
	LastKey:		.BYTE 1	//Last key pressed on keypad
	KeyCorrect:		.BYTE 1 //Flag indicating if key pressed is correct
	NewRound:		.BYTE 1 //Flag indicating if timer on potentiometer screens needs to be reset
	LCDBLOn:		.BYTE 1 //Flag indicating if LCD backlight should be on

	//Timer dependent
	PBDebounceTimer:	.BYTE 1 //Counts number of overflows of timer 2 before PBDisable flag is cleared
	CurrentCDTime:		.BYTE 1 //Stores the current value of the countdown
	CDOVFCount:			.BYTE 1 //Counts number of overflows of timer 0 for the operation of countdowns
	PotOVFCountdown:	.BYTE 1 //Counts number of overflows of timer 0 for a valid potentiometer read
	StrobeOVFCount: 	.BYTE 1 //Counts number of overflows of timer 0 before the strobe needs to be toggled on the win screen
	KeyOVFCount:		.BYTE 1 //Counts number of overflows of timer 0 before the correct number is accepted and a new round entered
	SpeakerOVFCountdown:.BYTE 1 //Counts number of overflows of timer 0 before speaker should be turned off
	LCDBLOVFCount:		.BYTE 1 //Counts number of overflows of timer 0 to time seconds prior to turning off LCD backlight
	LCDBLSecCountdown:	.BYTE 1 //Counts number of seconds of inactivity


//Define Macros
	.macro do_lcd_command
		push r16
		ldi r16, @0
		call lcd_command
		call lcd_wait
		pop r16
	.endmacro

	.macro do_lcd_data
		push r16
		mov r16, @0
		call lcd_data
		call lcd_wait
		pop r16
	.endmacro

	.macro do_lcd_data_i
		push r16
		ldi r16, @0
		call lcd_data
		call lcd_wait
		pop r16
	.endmacro

	.macro ScanKeypad //cannot place in function; loop terminated by button, ret would cause issues in stack
	//r16 (Row Mask)
	//r17 (Col Mask)
	//r18 (Read value)
	//r19 (Debounce Countdown)
	//r20 (Button)
	//r21 (Last button)
	//r22 (Mode)
	//r23 (Next Mode)
	//ZH and ZL

		ldi ZH, high(Mode)
		ldi ZL, low(Mode)
		ld r22, Z
		
		ldi ZH, high(LastKey)
		ldi ZL, low(LastKey)
		ldi r19, KEYRESETCOUNT

		//Continuous polling loop
		KeyWholeLoop:
			ldi r17, INITCOLMASK

		KeyColLoop:
			ldi r16, INITROWMASK
			sts PORTL, r17
			ldi r18, 0xFF

		KeyDelay:
			dec r18
			brne KeyDelay

		KeyRowLoop:
			lds r18, PINL
			and r18, r16
			brne KeyNextRow

		//If key detected
			//Determine button pressed in CCCCRRRR and store in r20
			mov r20, r17
			com r20
			or r20, r16

			//Turn on LCD and refresh idle timer if key is pressed
			SetLCDBL 1
			ResetLCDBLTimer
			
			//Compare to last button; if it's the same, skip, since the keypads are level sensitive and will read once per clock cycle
			ld r21, Z
			cp r21, r20
			breq KeyProcessFin

			//If key is valid
			st Z, r20
			call KeyProcess //Returns next mode or 0xFF in r23; 0xFF indicates staying on current mode

			cpi r23, 0xFF
			breq KeyProcessFin

			cpi r23, RESETPOTMODE
			brne CheckEnterCodeMode
			jmp ResetPotScreen
			
			CheckEnterCodeMode:
			cpi r23, ENTERCODEMODE
			brne CheckWinMode
			jmp EnterCodeScreen

			CheckWinMode:
			cpi r23, WINMODE
			brne KeyProcessFin
			jmp WinScreen
			
		KeyProcessFin:
			ldi r19, KEYRESETCOUNT
			cpi r22, FINDCODEMODE
			brne KeyNextRow
			clr r19
			st Z, r19 //Stores 0 in LastKey to read a continuous press when in find code mode
			ldi r19, KEYRESETCOUNT


		KeyNextRow:
			lsl r16
			cpi r16, 0x10
			breq KeyNextCol

			dec r19
			brne KeyRowLoop

			st Z, r19 //Stores 0 in LastKey so that any following key press is valid
			ldi r19, KEYRESETCOUNT
			
			//Disable motor
			in r24, PORTE
			andi r24, 0b11011111
			out PORTE, r24
			
			clr r24

			//Reset correct key flag
			ldi YH, high(KeyCorrect)
			ldi YL, low(KeyCorrect)
			st Y, r24

			//Reset correct key timer
			ldi YH, high(KeyOVFCount)
			ldi YL, low(KeyOVFCount)
			st Y, r24

			jmp KeyRowLoop

		KeyNextCol:
			lsl r17
			inc r17
			cpi r17, 0xFF
			breq GoToKeyWholeLoop
			jmp KeyColLoop

		GoToKeyWholeLoop:
			jmp KeyWholeLoop
	.endmacro

	.macro ADCRead
		push r16
		ldi r16, (3 << REFS0) | (0 << ADLAR) | (0 << MUX0)
		sts ADMUX, r16
		ldi r16, (1 << MUX5)
		sts ADCSRB, r16
		ldi r16, (1 << ADEN) | (1 << ADSC) | (1 << ADIE) | (5 << ADPS0)
		sts ADCSRA, r16
		pop r16
	.endmacro

	.macro divi //format: divi Rd, k; Rd/k : stores remainder in Rd result in R0
		push r16
		//mov R0, @0
		clr r16
		cpi r16, @1 //Ignore dividing by 0
		pop r16
		breq EndDivi

		clr R0 //intialise r0

		ContDivi:
		cpi @0, @1
		brlo EndDivi
		subi @0, @1
		inc R0
	
		rjmp ContDivi
	
		EndDivi:
	.endmacro

	.macro SetSpeakerTime
		push r16
		push ZH
		push ZL

		ldi ZH, high(SpeakerOVFCountDown)
		ldi ZL, low(SpeakerOVFCountDown)
		ldi r16, @0
		st Z, r16
		
		pop ZL
		pop ZH
		pop r16
	.endmacro

	.macro SetLCDBL
		push ZH
		push ZL
		push r16

		ldi ZH, high(LCDBLOn)
		ldi ZL, low(LCDBLOn)
		ldi r16, @0
		st Z, r16

		pop r16
		pop ZL
		pop ZH
	.endmacro

	.macro ResetLCDBLTimer
		push ZH
		push ZL
		push r16
		
		ldi r16, 5
		ldi ZH, high(LCDBLSecCountDown)
		ldi ZL, low(LCDBLSecCountDown)
		st Z, r16	

		clr r16
		ldi ZH, high(LCDBLOVFCount)
		ldi ZL, low(LCDBLOVFCount)
		st Z, r16

		pop r16
		pop ZL
		pop ZH
	.endmacro




.CSEG
	//Set up interrupt vectors
	.org 0
	jmp RESET

	.org INT0ADDR
	jmp PB0Pressed

	.org INT1ADDR
	jmp PB1Pressed
	
	.org OVF2ADDR
	jmp T2OVF

	.org OVF0ADDR
	jmp T0OVF

	.org ADCCADDR
	jmp ADCComplete

	.org OVF3ADDR
	jmp T3OVF


	RESET:
		//Disable global interrupts during setup
			cli

		//Set up stack pointer
			ldi r16, low(RAMEND)
			out SPL, r16
			ldi r16, high(RAMEND)
			out SPH, r16

		//Initialise variables
			clr r16

			ldi ZH, high(Code)
			ldi ZL, low(Code)
			st Z, r16
			
			ldi ZH, high(PotTarget)
			ldi ZL, low(PotTarget)
			st Z, r16
		
			ldi ZH, high(PotCorrect)
			ldi ZL, low(PotCorrect)
			st Z, r16
			
			ldi ZH, high(PotRoundClear)
			ldi ZL, low(PotRoundClear)
			st Z, r16			

			ldi ZH, high(RoundNum)
			ldi ZL, low(RoundNum)
			st Z, r16

			ldi ZH, high(Mode)
			ldi ZL, low(Mode)
			st Z, r16

			ldi ZH, high(LastKey)
			ldi ZL, low(LastKey)
			st Z, r16

			ldi ZH, high(KeyCorrect)
			ldi ZL, low(KeyCorrect)
			st Z, r16

			ldi ZH, high(PBDebounceTimer)
			ldi ZL, low(PBDebounceTimer)
			st Z, r16

			ldi ZH, high(CurrentCDTime)
			ldi ZL, low(CurrentCDTime)
			st Z, r16

			ldi ZH, high(CDOVFCount)
			ldi ZL, low(CDOVFCount)
			st Z, r16

			ldi ZH, high(CDEnable)
			ldi ZL, low(CDEnable)
			st Z, r16

			ldi ZH, high(StrobeOVFCount)
			ldi ZL, low(StrobeOVFCount)
			st Z, r16

			ldi ZH, high(KeyOVFCount)
			ldi ZL, low(KeyOVFCount)
			st Z, r16

			ldi ZH, high(SpeakerOVFCountdown)
			ldi ZL, low(SpeakerOVFCountdown)
			st Z, r16

			ldi ZH, high(LCDBLOVFCount)
			ldi ZL, low(LCDBLOVFCount)
			st Z, r16
			
			ldi r16, 20 //Default difficulty: easiest

			ldi ZH, high(CDTime)
			ldi ZL, low(CDTime)
			st Z, r16

			ldi r16, 5

			ldi ZH, high(LCDBLSecCountdown)
			ldi ZL, low(LCDBLSecCountdown)
			st Z, r16

			ldi r16, 1

			ldi ZH, high(NewRound)
			ldi ZL, low(NewRound)
			st Z, r16
			
			//Prevent reading bounces when game is reset using a push button
			ldi ZH, high(PBDisable)
			ldi ZL, low(PBDisable)
			st Z, r16

			ldi ZH, high(LCDBLOn)
			ldi ZL, low(LCDBLOn)
			st Z, r16

			ldi r16, 0xFF
			
			ldi ZH, high(PotOVFCountdown)
			ldi ZL, low(PotOVFCountdown)
			st Z, r16

			
		//Set up interrupts and timers
			//Push buttons
			ldi r16, (0b10 << ISC10) | (0b10 << ISC00) //Falling edge triggered
			sts EICRA, r16
			/*//Moved to start screen, when they are needed
			ldi r16, (1 << INT1) | (1 << INT0) //Unmask push button interrupts
			out EIMSK, r16
			*/

			//Timer 0
			clr r16 //Normal timer operation
			out TCCR0A, r16 
			ldi r16, (0b100 << CS00) //Prescaler 256
			out TCCR0B, r16
			ldi r16, (1 << TOIE0) //Enable timer 0 overflow interrupt
			sts TIMSK0, r16

			//Timer 2
			clr r16 //Normal timer operation
			sts TCCR2A, r16
			ldi r16, (0b010 << CS20) //Set prescaler to 8
			sts TCCR2B, r16
			ldi r16, (0b1 << TOIE2) //Enable timer 2 overflow interrupt
			sts TIMSK2, r16

			//Timer 3
			ldi r16, (0b10 << COM3B0) | (0b01 << WGM30) //Clear on output compare match, 8-bit Fast PWM
			sts TCCR3A, r16
			ldi r16, (0b01 << WGM32) | (0b100 << CS30) //8-bit Fast PWM, Prescaler 256
			sts TCCR3B, r16
			ser r16
			sts OCR3BL, r16
			ldi r16, (0b1 << TOIE3) //Enable timer 3 overflow interrupt
			sts TIMSK3, r16

		//Set up ports
			ser r16

			//LCD
			out DDRF, r16 // Port F: LCD Data
			out DDRA, r16 // Port A: LCD Control

			//LEDs: Lower bits = Lower LEDs
			out DDRC, r16 // Port C: LED Bar, 2-9 (Bottom eight)
			ldi r16, 0b00000011
			out DDRG, r16 // Port G: LED Bar, 0-1 (Top two)

			//Motor, Strobe LED & LCD Backlight
			ldi r16, 0b00111000
			out DDRE, r16 // Port E: Motor, LCD Backlight, Strobe LED (highest output bit -> lowest output bit)
			
			//Keypad
			ldi r16, 0b11110000
			sts DDRL, r16
			
			//Speaker
			ldi r16, 0b00000001
			out DDRB, r16

			//Push buttons
			clr r16
			out DDRD, r16
			
			//Initialise ports
			out PORTF, r16 
			out PORTA, r16
			out PORTC, r16
			out PORTG, r16
			out PORTE, r16
			out PORTB, r16
			
			ldi r16, 0b11101111 //Set up for reading letters only for start screen, enable pullup resistors
			sts PORTL, r16

		//Set up LCD
			SetLCDBL 1 //LCD backlight is initally on
			do_lcd_command 0b00111000 // 2x5x7
			call sleep_5ms
			do_lcd_command 0b00111000 // 2x5x7
			call sleep_1ms
			do_lcd_command 0b00111000 // 2x5x7
			do_lcd_command 0b00111000 // 2x5x7
			do_lcd_command 0b00001000 // display off?
			do_lcd_command 0b00000001 // clear display
			do_lcd_command 0b00000110 // increment, no display shift
			do_lcd_command 0b00001100 // Cursor on, bar, no blink

		//Enable global interrupts
			sei

	StartScreen:
		ldi ZH, high(Mode)
		ldi ZL, low(Mode)
		ldi r16, STARTMODE
		st Z, r16

		do_lcd_data_i '2'
		do_lcd_data_i '1'
		do_lcd_data_i '2'
		do_lcd_data_i '1'
		do_lcd_data_i ' '
		do_lcd_data_i '1'
		do_lcd_data_i '6'
		do_lcd_data_i 's'
		do_lcd_data_i '1'

		do_lcd_command ROW2LCD // shift cursor to beginning of 2nd line

		do_lcd_data_i 'S'
		do_lcd_data_i 'a'
		do_lcd_data_i 'f'
		do_lcd_data_i 'e'
		do_lcd_data_i ' '
		do_lcd_data_i 'C'
		do_lcd_data_i 'r'
		do_lcd_data_i 'a'
		do_lcd_data_i 'c'
		do_lcd_data_i 'k'
		do_lcd_data_i 'e'
		do_lcd_data_i 'r'
		
		do_lcd_data_i ' '
		do_lcd_data_i ' '
		do_lcd_data_i ' '

		do_lcd_data_i 'E' //Difficulty display; default is Easy

		ldi r16, (1 << INT1) | (1 << INT0) //Unmask push button interrupts
		out EIMSK, r16
		
		ScanKeypad		

	
	StartCDScreen:
		ldi ZH, high(Mode)
		ldi ZL, low(Mode)
		ldi r16, STARTCDMODE
		st Z, r16
		
		//Countdown active
		ldi ZH, high(CDEnable)
		ldi ZL, low(CDEnable)
		ldi r16, 1
		st Z, r16

		do_lcd_command CLEARLCD

		do_lcd_data_i '2'
		do_lcd_data_i '1'
		do_lcd_data_i '2'
		do_lcd_data_i '1'
		do_lcd_data_i ' '
		do_lcd_data_i '1'
		do_lcd_data_i '6'
		do_lcd_data_i 's'
		do_lcd_data_i '1'

		do_lcd_command ROW2LCD

		do_lcd_data_i 'S'
		do_lcd_data_i 't'
		do_lcd_data_i 'a'
		do_lcd_data_i 'r'
		do_lcd_data_i 't'
		do_lcd_data_i 'i'
		do_lcd_data_i 'n'
		do_lcd_data_i 'g'
		do_lcd_data_i ' '
		do_lcd_data_i 'i'
		do_lcd_data_i 'n'
		do_lcd_data_i ' '
		do_lcd_data_i '3'
		do_lcd_data_i '.'
		do_lcd_data_i '.'
		do_lcd_data_i '.'

		do_lcd_command CURSORL
		do_lcd_command CURSORL
		do_lcd_command CURSORL
		do_lcd_command CURSORL
		
		//Reset timer
		ldi ZH, high(CDOVFCount)
		ldi ZL, low(CDOVFCount)
		clr r16
		st Z, r16
		
		//Initialise countdown
		ldi ZH, high(CurrentCDTime)
		ldi ZL, low(CurrentCDTime)
		ldi r16, 3
		st Z, r16

		StartCDWait:
			ld r16, Z
			subi r16, -NUMTOASCII
			do_lcd_data r16
			do_lcd_command CURSORL
			cpi r16, NUMTOASCII //If value is 0
			breq ResetPotScreen
			rjmp StartCDWait

		
	ResetPotScreen:
		ldi ZH, high(Mode)
		ldi ZL, low(Mode)
		ldi r16, RESETPOTMODE
		st Z, r16

		//Countdown active
		ldi ZH, high(CDEnable)
		ldi ZL, low(CDEnable)
		ldi r16, 1
		st Z, r16

		//Disable motor
		in r16, PORTE
		andi r16, 0b11011111
		out PORTE, r16
		
		//Clear flag
		ldi ZH, high(KeyCorrect)
		ldi ZL, low(KeyCorrect)
		clr r16
		st Z, r16
		
		do_lcd_command CLEARLCD

		do_lcd_data_i 'R'
		do_lcd_data_i 'e'
		do_lcd_data_i 's'
		do_lcd_data_i 'e'
		do_lcd_data_i 't'
		do_lcd_data_i ' '
		do_lcd_data_i 'P'
		do_lcd_data_i 'O'
		do_lcd_data_i 'T'
		do_lcd_data_i ' '
		do_lcd_data_i 't'
		do_lcd_data_i 'o'
		do_lcd_data_i ' '
		do_lcd_data_i '0'

		do_lcd_command ROW2LCD

		do_lcd_data_i 'R'
		do_lcd_data_i 'e'
		do_lcd_data_i 'm'
		do_lcd_data_i 'a'
		do_lcd_data_i 'i'
		do_lcd_data_i 'n'
		do_lcd_data_i 'i'
		do_lcd_data_i 'n'
		do_lcd_data_i 'g'
		do_lcd_data_i ':'
		do_lcd_data_i ' '
		do_lcd_data_i ' '
		do_lcd_data_i ' '

		ldi ZH, high(NewRound)
		ldi ZL, low(NewRound)
		ld r16, Z
		cpi r16, 0
		breq EndResetPotTimer
		
			//Clear the NewRound flag
			clr r16
			st Z, r16
			
			SetSpeakerTime MS500

			//Reset Timer
			ldi ZH, high(CDOVFCount)
			ldi ZL, low(CDOVFCount)
			clr r16
			st Z, r16
		
			//Set countdown time
			ldi ZH, high(CDTime)
			ldi ZL, low(CDTime)
			ld r16, Z
			ldi ZH, high(CurrentCDTime)
			ldi ZL, low(CurrentCDTime)
			st Z, r16
			
			do_lcd_command CURSORL
			do_lcd_command CURSORL
			call UpdateCD

			//Determine potentiometer target from timer 2
			ldi ZH, high(PotTarget)
			ldi ZL, low(PotTarget)
			lds r16, TCNT2
			//Potentiometer is 6 bit value
			lsr r16
			lsr r16
			st Z, r16

		EndResetPotTimer:
			ldi ZH, high(CurrentCDTime)
			ldi ZL, low(CurrentCDTime)

			ldi YH, high(PotValue)
			ldi YL, low(PotValue)

			ldi XH, high(PotOVFCountdown)
			ldi XL, low(PotOVFCountdown)
			ldi r16, MS500
			st X, r16

			clr r16

			ldi XH, high(PotCorrect)
			ldi XL, low(PotCorrect)
			st X, r16

			ldi XH, high(PotRoundClear)
			ldi XL, low(PotRoundClear)
			st X, r16

		ResetPotLoop:
			
			ldi XH, high(PotRoundClear)
			ldi XL, low(PotRoundClear)
			ld r16, X
			cpi r16, 1
			breq FindPotScreen

			//Check potentiometer
			ADCRead
			ld r17, Y
			cpi r17, 0
			brne ResetPotWrongPos

			ldi XH, high(PotCorrect)
			ldi XL, low(PotCorrect)
			ldi r16, 1
			st X, r16
			rjmp UpdateResetPotTimer
			
			ResetPotWrongPos:
				ldi XH, high(PotOVFCountdown)
				ldi XL, low(PotOVFCountdown)
				ldi r16, MS500
				st X, r16

				ldi XH, high(PotCorrect)
				ldi XL, low(PotCorrect)
				clr r16
				st X, r16

			UpdateResetPotTimer:
				ld r16, Z
				cpi r16, 0
				brne ResetPotCDContinue //Check for game over
				jmp LoseScreen
				
				ResetPotCDContinue:
				do_lcd_command CURSORL
				do_lcd_command CURSORL
				call UpdateCD

			rjmp ResetPotLoop


	FindPotScreen:
		ldi ZH, high(Mode)
		ldi ZL, low(Mode)
		ldi r16, FINDPOTMODE
		st Z, r16

		//Countdown active
		ldi ZH, high(CDEnable)
		ldi ZL, low(CDEnable)
		ldi r16, 1
		st Z, r16
		
		do_lcd_command CLEARLCD

		do_lcd_data_i 'F'
		do_lcd_data_i 'i'
		do_lcd_data_i 'n'
		do_lcd_data_i 'd'
		do_lcd_data_i ' '
		do_lcd_data_i 'P'
		do_lcd_data_i 'O'
		do_lcd_data_i 'T'
		do_lcd_data_i ' '
		do_lcd_data_i 'P'
		do_lcd_data_i 'o'
		do_lcd_data_i 's'

		do_lcd_command ROW2LCD

		do_lcd_data_i 'R'
		do_lcd_data_i 'e'
		do_lcd_data_i 'm'
		do_lcd_data_i 'a'
		do_lcd_data_i 'i'
		do_lcd_data_i 'n'
		do_lcd_data_i 'i'
		do_lcd_data_i 'n'
		do_lcd_data_i 'g'
		do_lcd_data_i ':'
		do_lcd_data_i ' '
		do_lcd_data_i ' '
		do_lcd_data_i ' '
		
		ldi ZH, high(CurrentCDTime)
		ldi ZL, low(CurrentCDTime)

		ldi YH, high(PotValue)
		ldi YL, low(PotValue)
		
		//r18 stores potentiometer target
		ldi XH, high(PotTarget)
		ldi XL, low(PotTarget)
		ld r18, X

		ldi XH, high(PotOVFCountdown)
		ldi XL, low(PotOVFCountdown)
		ldi r16, MS1000
		st X, r16

		clr r16

		ldi XH, high(PotCorrect)
		ldi XL, low(PotCorrect)
		st X, r16

		ldi XH, high(PotRoundClear)
		ldi XL, low(PotRoundClear)
		st X, r16

		FindPotLoop:
			
			ldi XH, high(PotRoundClear)
			ldi XL, low(PotRoundClear)
			ld r16, X
			cpi r16, 1
			brne FindPotReadADC
			jmp FindCodeScreen	
			
			FindPotReadADC:
			ADCRead
			ld r17, Y
			cp r17, r18
			brne FindPotWrongPos

			ser r16
			out PORTC, r16
			ldi r16, 0b00000011
			out PORTG, r16

			ldi XH, high(PotCorrect)
			ldi XL, low(PotCorrect)
			ldi r16, 1
			st X, r16
			rjmp UpdateFindPotTimer
			
			FindPotWrongPos:
				//Flags still set from cp r17, r18
				brlt PotLTTarget
				clr r16
				out PORTC, r16
				out PORTG, r16
				jmp ResetPotScreen
				
				PotLTTarget:
				ldi XH, high(PotOVFCountdown)
				ldi XL, low(PotOVFCountdown)
				ldi r16, MS1000
				st X, r16

				ldi XH, high(PotCorrect)
				ldi XL, low(PotCorrect)
				clr r16
				st X, r16
				
				//Check for within 32
				//Since going over the value causes a return to previous screen, no need to check for if value is 32 higher than target
				mov r19, r17
				subi r19, -0b00000010
				cp r18, r19
				brlt Within32


				//Check for within 48
				//Since going over the value causes a return to previous screen, no need to check for if value is 48 higher than target
				mov r19, r17
				subi r19, -0b00000011
				cp r18, r19
				brlt Within48

				rjmp UpdateFindPotTimer

				Within32:
				ser r16
				out PORTC, r16
				ldi r16, 0b00000001
				out PORTG, r16
				rjmp UpdateFindPotTimer

				Within48:
				ser r16
				out PORTC, r16
				clr r16
				out PORTG, r16
				rjmp UpdateFindPotTimer


			UpdateFindPotTimer:
				ld r16, Z
				cpi r16, 0
				brne FindPotCDContinue //Check for game over
				jmp LoseScreen
				
				FindPotCDContinue:
				do_lcd_command CURSORL
				do_lcd_command CURSORL
				call UpdateCD

			rjmp FindPotLoop


	FindCodeScreen:
		ldi ZH, high(Mode)
		ldi ZL, low(Mode)
		ldi r16, FINDCODEMODE
		st Z, r16

		//Countdown inactive
		ldi ZH, high(CDEnable)
		ldi ZL, low(CDEnable)
		clr r16
		st Z, r16
		
		//Turn off LED bar
		clr r16
		out PORTC, r16
		out PORTG, r16

		do_lcd_command CLEARLCD

		do_lcd_data_i 'P'
		do_lcd_data_i 'o'
		do_lcd_data_i 's'
		do_lcd_data_i 'i'
		do_lcd_data_i 't'
		do_lcd_data_i 'i'
		do_lcd_data_i 'o'
		do_lcd_data_i 'n'
		do_lcd_data_i ' '
		do_lcd_data_i 'F'
		do_lcd_data_i 'o'
		do_lcd_data_i 'u'
		do_lcd_data_i 'n'
		do_lcd_data_i 'd'
		do_lcd_data_i '!'

		do_lcd_command ROW2LCD

		do_lcd_data_i 'S'
		do_lcd_data_i 'c'
		do_lcd_data_i 'a'
		do_lcd_data_i 'n'
		do_lcd_data_i ' '
		do_lcd_data_i 'f'
		do_lcd_data_i 'o'
		do_lcd_data_i 'r'
		do_lcd_data_i ' '
		do_lcd_data_i 'n'
		do_lcd_data_i 'u'
		do_lcd_data_i 'm'
		do_lcd_data_i 'b'
		do_lcd_data_i 'e'
		do_lcd_data_i 'r'

		ldi ZH, high(KeyCorrect)
		ldi ZL, low(KeyCorrect)
		clr r16
		st Z, r16

		ScanKeypad

	EnterCodeScreen:
		ldi ZH, high(Mode)
		ldi ZL, low(Mode)
		ldi r16, ENTERCODEMODE
		st Z, r16

		//Countdown inactive
		ldi ZH, high(CDEnable)
		ldi ZL, low(CDEnable)
		clr r16
		st Z, r16

		//Disable motor
		in r16, PORTE
		andi r16, 0b11011111
		out PORTE, r16

		clr r16
		
		//Clear flag
		ldi ZH, high(KeyCorrect)
		ldi ZL, low(KeyCorrect)
		st Z, r16
		
		//Reset round number to keep track of which digit is correct
		ldi ZH, high(RoundNum)
		ldi ZL, low(RoundNum)
		st Z, r16
		
		do_lcd_command CLEARLCD

		do_lcd_data_i 'E'
		do_lcd_data_i 'n'
		do_lcd_data_i 't'
		do_lcd_data_i 'e'
		do_lcd_data_i 'r'
		do_lcd_data_i ' '
		do_lcd_data_i 'C'
		do_lcd_data_i 'o'
		do_lcd_data_i 'd'
		do_lcd_data_i 'e'
		
		do_lcd_command ROW2LCD

		ScanKeypad

	WinScreen:
		ldi ZH, high(Mode)
		ldi ZL, low(Mode)
		ldi r16, WINMODE
		st Z, r16

		//Countdown inactive
		ldi ZH, high(CDEnable)
		ldi ZL, low(CDEnable)
		clr r16
		st Z, r16

		SetSpeakerTime MS1000

		do_lcd_command CLEARLCD
		
		do_lcd_data_i 'G'
		do_lcd_data_i 'a'
		do_lcd_data_i 'm'
		do_lcd_data_i 'e'
		do_lcd_data_i ' '
		do_lcd_data_i 'c'
		do_lcd_data_i 'o'
		do_lcd_data_i 'm'
		do_lcd_data_i 'p'
		do_lcd_data_i 'l'
		do_lcd_data_i 'e'
		do_lcd_data_i 't'
		do_lcd_data_i 'e'

		do_lcd_command ROW2LCD

		do_lcd_data_i 'Y'
		do_lcd_data_i 'o'
		do_lcd_data_i 'u'
		do_lcd_data_i ' '
		do_lcd_data_i 'W'
		do_lcd_data_i 'i'
		do_lcd_data_i 'n'
		do_lcd_data_i '!'

		ScanKeypad

	LoseScreen:
		ldi ZH, high(Mode)
		ldi ZL, low(Mode)
		ldi r16, LOSEMODE
		st Z, r16

		//Countdown inactive
		ldi ZH, high(CDEnable)
		ldi ZL, low(CDEnable)
		clr r16
		st Z, r16

		SetSpeakerTime MS1000
		
		//Turn off LEDs
		clr r16
		out PORTC, r16
		out PORTG, r16

		do_lcd_command CLEARLCD
		
		do_lcd_data_i 'G'
		do_lcd_data_i 'a'
		do_lcd_data_i 'm'
		do_lcd_data_i 'e'
		do_lcd_data_i ' '
		do_lcd_data_i 'O'
		do_lcd_data_i 'v'
		do_lcd_data_i 'e'
		do_lcd_data_i 'r'

		do_lcd_command ROW2LCD

		do_lcd_data_i 'Y'
		do_lcd_data_i 'o'
		do_lcd_data_i 'u'
		do_lcd_data_i ' '
		do_lcd_data_i 'L'
		do_lcd_data_i 'o'
		do_lcd_data_i 's'
		do_lcd_data_i 'e'
		do_lcd_data_i '!'

		ScanKeypad


	////////////////////////////////Functions/////////////////////////////////
	
	KeyProcess:
	//Inputs:
	//r20 (Button)
	//r22 (Mode)

	//Output:
	//r23 (Next Mode)
		
		push r16
		push r17
		push r18
		push r19
		push r20
		push r21
		push r22
		push ZH
		push ZL

	//Determine which mode
		cpi r22, STARTMODE
		breq KeyStartMode

		cpi r22, FINDCODEMODE
		brne KeyNotFindCode
		jmp KeyFindCodeMode
		
		KeyNotFindCode:

		cpi r22, ENTERCODEMODE
		brne KeyNotEnterCode
		jmp KeyEnterCodeMode
		
		KeyNotEnterCode:

		cpi r22, LOSEMODE
		breq KeypadReset
		cpi r22, WINMODE
		breq KeypadReset

		jmp EndKeyProcess

		KeypadReset:
			jmp Reset


		KeyStartMode:
			ldi r23, 0xFF //Pressing a keypad button does not exit the start screen

			ldi ZH, high(CDTime)
			ldi ZL, low(CDTime)

			cpi r20, 0b10000001
			breq EasyDifficulty
			cpi r20, 0b10000010
			breq MedDifficulty
			cpi r20, 0b10000100
			breq HardDifficulty
			cpi r20, 0b10001000
			breq ExtremeDifficulty
			jmp EndKeyProcess //Skip if button pressed was not a letter

			EasyDifficulty:
				ldi r16, 20
				st Z, r16
				do_lcd_command CURSORL
				do_lcd_data_i 'E'
				jmp EndKeyProcess

			MedDifficulty:
				ldi r16, 15
				st Z, r16
				do_lcd_command CURSORL
				do_lcd_data_i 'M'
				jmp EndKeyProcess

			HardDifficulty:
				ldi r16, 10
				st Z, r16
				do_lcd_command CURSORL
				do_lcd_data_i 'H'
				jmp EndKeyProcess

			ExtremeDifficulty:
				ldi r16, 6
				st Z, r16
				do_lcd_command CURSORL
				do_lcd_data_i 'X'
				jmp EndKeyProcess

		KeyFindCodeMode:
			ldi r23, 0xFF //Default return; timers will indicate if mode needs to be changed
			
			ldi ZH, high(RoundNum)
			ldi ZL, low(RoundNum)
			ld r17, Z

			//Determine correct digit for the round
			ldi ZH, high(Code)
			ldi ZL, low(Code)
			add ZL, r17
			clr r17
			adc ZH, r17
			
			ld r16, Z
			cp r20, r16
			breq FoundCorrect
			
				//Disable motor
				in r18, PORTE
				andi r18, 0b11011111
				out PORTE, r18
			
				clr r18

				//Reset correct key flag
				ldi ZH, high(KeyCorrect)
				ldi ZL, low(KeyCorrect)
				st Z, r18

				//Reset correct key timer
				ldi ZH, high(KeyOVFCount)
				ldi ZL, low(KeyOVFCount)
				st Z, r18

				rjmp EndKeyProcess

			FoundCorrect:
				//Enable motor
				in r18, PORTE
				ori r18, 0b00100000
				out PORTE, r18

				//Set correct key flag
				ldi ZH, high(KeyCorrect)
				ldi ZL, low(KeyCorrect)
				ldi r18, 1
				st Z, r18

				ldi ZH, high(NewRound)
				ldi ZL, low(NewRound)
				ld r18, Z
				
				cpi r18, 0
				breq EndKeyProcess
				
				ldi ZH, high(RoundNum)
				ldi ZL, low(RoundNum)
				ld r18, Z
				inc r18
				st Z, r18
				
				cpi r18, 3
				breq GoToEnterCodeMode
				
				ldi r23, RESETPOTMODE
				rjmp EndKeyProcess

				GoToEnterCodeMode:
				ldi r23, ENTERCODEMODE
				rjmp EndKeyProcess

		KeyEnterCodeMode:
			ldi r23, 0xFF //Default return; incorrect and 3 correct keys will change this
			
			ldi ZH, high(RoundNum)
			ldi ZL, low(RoundNum)
			ld r17, Z

			//Determine correct digit for the round
			ldi ZH, high(Code)
			ldi ZL, low(Code)
			add ZL, r17
			clr r17
			adc ZH, r17
			
			ld r16, Z
			cp r20, r16
			breq KeyCorrectCode
			
			//Restart enter code if incorrect number entered
			ldi r23, ENTERCODEMODE

			rjmp EndKeyProcess

			KeyCorrectCode:
				//If correct code digit is entered, increment round counter so that the correct digit is checked next time
				ldi ZH, high(RoundNum)
				ldi ZL, low(RoundNum)
				ld r17, Z
				inc r17
				st Z, r17

				do_lcd_data_i '*'
				
				//Check if game has been won
				cpi r17, 3
				brne EndKeyProcess
				
				ldi r23, WINMODE

		EndKeyProcess:
			pop ZL
			pop ZH
			pop r22
			pop r21
			pop r20
			pop r19
			pop r18
			pop r17
			pop r16
			ret

	UpdateCD:
	//Input: CDTime in r16
	//Output: Changes display of countdown time on LCD
		push r16
		push r17
		push r0
		push r1
		
		Tens:
			divi r16, 10
			mov r17, R0 //move result to register which subi works with
			subi r17, -NumToASCII
			cpi r17, NumToASCII
			breq LT10 //Write a space in tens place if result is less than 10

			do_lcd_data r17
			rjmp Ones

			LT10:
				do_lcd_data_i ' '
	
		Ones:
			divi r16, 1
			mov r17, R0 //move result to register which subi works with
			subi r17, -NumToASCII
			do_lcd_data r17
		
		EndUpdateCD:
		pop r1
		pop r0
		pop r17
		pop r16
		ret

	DIVW: //Divides word stored in r17:r16 by value in r18. Stores result in R0, and remainder in r17:r16. Assumed r18 <= 255
		push r18
		push r19
	
		clr r19
		cp r19, r18 //Ignore dividing by 0

		breq EndDivw

		clr r0 //intialise r0

		ContDivw:
			cp r16, r18
			cpc r17, r19
			brlo EndDivw
			sub r16, r18
			sbc r17, r19
			inc R0
	
			rjmp ContDivw
	
		EndDivw:
		pop r19
		pop r18
		ret
	
	NumToKey: //Takes binary representation of a single decimal digit in r0 and returns the keypad code for it in CCCCRRRR form
		push r16

		mov r16, r0

		cpi r16, 0
		breq Key0

		cpi r16, 1
		breq Key1

		cpi r16, 2
		breq Key2

		cpi r16, 3
		breq Key3

		cpi r16, 4
		breq Key4

		cpi r16, 5
		breq Key5

		cpi r16, 6
		breq Key6

		cpi r16, 7
		breq Key7

		cpi r16, 8
		breq Key8

		cpi r16, 9
		breq Key9

		Key0:
		ldi r16, 0b0010_1000
		rjmp EndNumToKey

		Key1:
		ldi r16, 0b0001_0001
		rjmp EndNumToKey

		Key2:
		ldi r16, 0b0010_0001
		rjmp EndNumToKey

		Key3:
		ldi r16, 0b0100_0001
		rjmp EndNumToKey

		Key4:
		ldi r16, 0b0001_0010
		rjmp EndNumToKey

		Key5:
		ldi r16, 0b0010_0010
		rjmp EndNumToKey

		Key6:
		ldi r16, 0b0100_0010
		rjmp EndNumToKey

		Key7:
		ldi r16, 0b0001_0100
		rjmp EndNumToKey

		Key8:
		ldi r16, 0b0010_0100
		rjmp EndNumToKey

		Key9:
		ldi r16, 0b0100_0100
		rjmp EndNumToKey

		EndNumToKey:
		mov r0, r16

		pop r16
		ret

	////////////////////////////////Interrupts////////////////////////////////
	PB0Pressed:
		jmp Reset

	PB1Pressed:
		push r16
		in r16, SREG
		push r16
		push r17
		push ZH
		push ZL
		
		//Turn on LCD and refresh idle timer if button is pressed
		SetLCDBL 1
		ResetLCDBLTimer

		ldi ZH, high(PBDisable)
		ldi ZL, low(PBDisable)
		ld r16, Z
		cpi r16, 1
		brne PBEnabled
		jmp EndPB1Pressed
		
		PBEnabled:
		ldi r16, 1
		st Z, r16

		ldi ZH, high(PBDebounceTimer)
		ldi ZL, low(PBDebounceTimer)
		clr r16
		st Z, r16

		ldi ZH, high(Mode)
		ldi ZL, low(Mode)
		ld r16, Z
		
		cpi r16, STARTMODE
		breq GoToStartCDScreen

		cpi	r16, WINMODE
		breq PB1ResetGame
		cpi r16, LOSEMODE
		breq PB1ResetGame
		rjmp EndPB1Pressed

		PB1ResetGame:
		jmp Reset

		GoToStartCDScreen: //Next screen operates independently of previous screen's registers
		pop ZL
		pop ZH
		pop r17
		pop r16
		out SREG, r16
		pop r16
		
		ldi r18, low(1000)
		ldi r19, high(1000)	
		
		//Determines a random 3 digit code based on timer 0 and 2
		lds r16, TCNT0
		lds r17, TCNT2

		//Crop from 16 to 10 bits (max 1024)
		lsr r17
		ror r16
		lsr r17
		ror r16
		lsr r17
		ror r16
		lsr r17
		ror r16
		lsr r17
		ror r16
		lsr r17
		ror r16

		cp r16, r18
		cpc r17, r19
		brlt StoreRandom
		subi r16, 24
		
		StoreRandom:
			ldi ZH, high(Code)
			ldi ZL, low(Code)

			ldi r18, 100
			call divw
			call NumToKey
			st Z+, r0

			ldi r18, 10
			call divw
			call NumToKey
			st Z+, r0

			mov r0, r16
			call NumToKey
			st Z+, r0
		
		//reti increments SP by 2 and enables interrupts
		in r16, SPL
		in r17, SPH
		subi r16, low(-2)
		sbci r17, high(-2)
		out SPL, r16
		out SPH, r17
		sei
		jmp StartCDScreen
		
		EndPB1Pressed:
		pop ZL
		pop ZH
		pop r17
		pop r16
		out SREG, r16
		pop r16	
		reti
	
	ADCComplete:
		push r16
		in r16, SREG
		push r16
		push r17
		push ZH
		push ZL
 
		lds r16, ADCL
		lds r17, ADCH

		//ADC >> 4 = ADC/16; gives value to compare to where equality is +/- 16 of actual value
		lsr r17
		ror r16
		lsr r17
		ror r16
		lsr r17
		ror r16
		lsr r17
		ror r16

		ldi ZH, high(PotValue)
		ldi ZL, low(PotValue)
		st Z, r16

		pop ZL
		pop ZH
		pop r17
		pop r16
		out SREG, r16
		pop r16
		reti

	T0OVF:
		push r16
		in r16, SREG
		push r16
		push r17
		push r18
		push ZH
		push ZL
		
		ldi ZH, high(Mode)
		ldi ZL, low(Mode)
		ld r16, Z

		ldi ZH, high(SpeakerOVFCountDown)
		ldi ZL, low(SpeakerOVFCountDown)
		ld r17, Z

		//If SpeakerOVFCountdown is 0, do not make a sound or decrement
		cpi r17, 0
		breq T0AfterSpeaker
			dec r17
			st Z, r17
			
			//Toggle the speaker output; produces a wave at ~122 Hz
			in r17, PORTB
			ldi r18, (1 << 0)
			eor r17, r18
			out PORTB, r17


		T0AfterSpeaker:
			//Countdown timers
			ldi ZH, high(CDOVFCount)
			ldi ZL, low(CDOVFCount)
			ld r17, Z
			inc r17
			st Z, r17

			cpi r17, MS1000
			breq DecCDTime

		T0AfterCD:

			//Check if potentiometer is at correct position
			ldi ZH, high(PotCorrect)
			ldi ZL, low(PotCorrect)
			ld r17, Z
			cpi r17, 0
			breq T0AfterPot
		
			//If potentiometer read is correct, count time held at correct position
			ldi ZH, high(PotOVFCountdown)
			ldi ZL, low(PotOVFCountdown)
			ld r17, Z
			dec r17
			st Z, r17
			cpi r17, 0
			brne T0AfterPot
			jmp SetPotRoundClear
		
		T0AfterPot: //Find code

			cpi r16, FINDCODEMODE
			brne T0AfterFindCode

			//Check if correct key is pressed
			ldi ZH, high(KeyCorrect)
			ldi ZL, low(KeyCorrect)
			ld r17, Z
			cpi r17, 0
			breq T0KeyIncorrect

			//If key pressed is correct, count time held at correct position
			ldi ZH, high(KeyOVFCount)
			ldi ZL, low(KeyOVFCount)
			ld r17, Z
			inc r17
			st Z, r17
			cpi r17, MS1000
			breq SetKeyRoundClear
			
			rjmp T0AfterFindCode

			T0KeyIncorrect:
			//If key pressed is incorrect, clear time held at correct position
			ldi ZH, high(KeyOVFCount)
			ldi ZL, low(KeyOVFCount)
			clr r17
			st Z, r17


		T0AfterFindCode:

			//Strobe
			cpi r16, WINMODE
			brne T0AfterStrobe

			ldi ZH, high(StrobeOVFCount)
			ldi ZL, low(StrobeOVFCount)
			ld r17, Z
			inc r17
			st Z, r17
			cpi r17, MS250
			breq StrobeToggle

		T0AfterStrobe:
			//LCD Backlight
			cpi r16, STARTMODE
			breq LCDBLTick
			cpi r16, WINMODE
			breq LCDBLTick
			cpi r16, LOSEMODE
			breq LCDBLTick

			rjmp EndT0OVF

			LCDBLTick:
				ldi ZH, high(LCDBLOVFCount)
				ldi ZL, low(LCDBLOVFCount)
				ld r17, Z
				inc r17
				st Z, r17
				cpi r17, MS1000
				breq LCDBLSecond

			rjmp EndT0OVF

		DecCDTime:
			//Reset CDOVFCount
			clr r17
			st Z, r17

			//Check if countdown is enabled
			ldi ZH, high(CDEnable)
			ldi ZL, low(CDEnable)
			ld r17, Z
			cpi r17, 0
			breq CDSkipSpeaker
			
			SetSpeakerTime MS250

			CDSkipSpeaker:

			ldi ZH, high(CurrentCDTime)
			ldi ZL, low(CurrentCDTime)
			ld r17, Z
			dec r17
			st Z, r17

			rjmp T0AfterCD
		
		SetPotRoundClear:
			ldi ZH, high(PotRoundClear)
			ldi ZL, low(PotRoundClear)
			ldi r17, 1
			st Z, r17
					
			rjmp T0AfterPot
		
		SetKeyRoundClear:
			ldi ZH, high(NewRound)
			ldi ZL, low(NewRound)
			ldi r17, 1
			st Z, r17
					
			rjmp T0AfterFindCode

		StrobeToggle:
			//Reset StrobeOVFCount
			clr r17
			st Z, r17

			in r17, PORTE
			ldi r18, (1 << 3)
			eor r18, r17
			out PORTE, r18

			rjmp T0AfterStrobe
		
		LCDBLSecond:
			//Reset LCDBLOVFCount
			clr r17
			st Z, r17

			ldi ZH, high(LCDBLSecCountdown)
			ldi ZL, low(LCDBLSecCountdown)
			ld r17, Z
			cpi r17, 0
			breq LCDBLSecSkipDec
			
			dec r17
			st Z, r17

			brne EndT0OVF //Decrement and do nothing if countdown has not expired yet

			LCDBLSecSkipDec:
				SetLCDBL 0


		EndT0OVF:
			pop ZL
			pop ZH
			pop r18
			pop r17
			pop r16
			out SREG, r16
			pop r16	
			reti


	T2OVF:
		push r16
		in r16, SREG
		push r16
		push ZH
		push ZL

		ldi ZH, high(PBDebounceTimer)
		ldi ZL, low(PBDebounceTimer)
		ld r16, Z
		inc r16
		st Z, r16

		//Count to 8 = 1ms
		cpi r16, 240
		brne EndT2OVF //Skip if 25ms have not elapsed

		clr r16
		st Z, r16

		ldi ZH, high(PBDisable)
		ldi ZL, low(PBDisable)
		st Z, r16 //Clear flag

		EndT2OVF:
		pop ZL
		pop ZH
		pop r16
		out SREG, r16
		pop r16
		reti

	T3OVF:
		push r16
		in r16, SREG
		push r16
		push r17
		push ZH
		push ZL

		lds r17, OCR3BL

		ldi ZH, high(LCDBLOn)
		ldi ZL, low(LCDBLOn)
		ld r16, Z
		
		cpi r16, 0
		breq FadeLCDBLOff

		FadeLCDBLOn:
			cpi r17, 0xFF
			breq EndT3OVF
			inc r17
			sts OCR3BL, r17
			cpi r17, 0xFF
			breq EndT3OVF
			inc r17
			sts OCR3BL, r17
			rjmp EndT3OVF
			
		
		FadeLCDBLOff:
			cpi r17, 0
			breq EndT3OVF
			dec r17
			sts OCR3BL, r17
			breq EndT3OVF
			dec r17
			sts OCR3BL, r17


		EndT3OVF:
			pop ZL
			pop ZH
			pop r17
			pop r16
			out SREG, r16
			pop r16	
			reti	

	////////////////////////////////////LCD////////////////////////////////////
	.equ LCD_RS = 7
	.equ LCD_E = 6
	.equ LCD_RW = 5
	.equ LCD_BE = 4

	.macro lcd_set
		sbi PORTA, @0
	.endmacro
	.macro lcd_clr
		cbi PORTA, @0
	.endmacro

	;
	; Send a command to the LCD (r16)
	;

	lcd_command:
		out PORTF, r16
		rcall sleep_1ms
		lcd_set LCD_E
		rcall sleep_1ms
		lcd_clr LCD_E
		rcall sleep_1ms
		ret

	lcd_data:
		out PORTF, r16
		lcd_set LCD_RS
		rcall sleep_1ms
		lcd_set LCD_E
		rcall sleep_1ms
		lcd_clr LCD_E
		rcall sleep_1ms
		lcd_clr LCD_RS
		ret

	lcd_wait:
		push r16
		clr r16
		out DDRF, r16
		out PORTF, r16
		lcd_set LCD_RW
	lcd_wait_loop:
		rcall sleep_1ms
		lcd_set LCD_E
		rcall sleep_1ms
		in r16, PINF
		lcd_clr LCD_E
		sbrc r16, 7
		rjmp lcd_wait_loop
		lcd_clr LCD_RW
		ser r16
		out DDRF, r16
		pop r16
		ret

	.equ F_CPU = 16000000
	.equ DELAY_1MS = F_CPU / 4 / 1000 - 4
	; 4 cycles per iteration - setup/call-return overhead

	sleep_1ms:
		push r24
		push r25
		ldi r25, high(DELAY_1MS)
		ldi r24, low(DELAY_1MS)
	delayloop_1ms:
		sbiw r25:r24, 1
		brne delayloop_1ms
		pop r25
		pop r24
		ret

	sleep_5ms:
		rcall sleep_1ms
		rcall sleep_1ms
		rcall sleep_1ms
		rcall sleep_1ms
		rcall sleep_1ms
		ret
	//////////////////////////////////END LCD//////////////////////////////////
