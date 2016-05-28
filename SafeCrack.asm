.include "m2560def.inc"

//Define Macros
	.macro do_lcd_command
		push r16
		ldi r16, @0
		rcall lcd_command
		rcall lcd_wait
		pop r16
	.endmacro
	.macro do_lcd_data
		push r16
		mov r16, @0
		rcall lcd_data
		rcall lcd_wait
		pop r16
	.endmacro
	.macro do_lcd_data_i
		push r16
		ldi r16, @0
		rcall lcd_data
		rcall lcd_wait
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
			jmp ResetPotScreen
			cpi r23, ENTERCODEMODE
			jmp EnterCodeScreen
			

		KeyProcessFin:
			ldi r19, KEYRESETCOUNT

		KeyNextRow:
			lsl r16
			cpi r16, 0x10
			breq KeyNextCol
			dec r19
			brne KeyRowLoop

			st Z, r19 //Stores 0 in LastKey so that any following key press is valid
			ldi r19, KEYRESETCOUNT
			jmp KeyRowLoop

		KeyNextCol:
			lsl r17
			inc r17
			cpi r17, 0xFF
			breq KeyWholeLoop
			jmp KeyColLoop
	.endmacro

//Define Constants
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

.DSEG
	Code: 		.BYTE 3 //Correct code
	PotTarget: 	.BYTE 2 //Potentiometer target
	RoundNum: 	.BYTE 1 //Number of rounds played
	CDTime:		.BYTE 1	//Countdown time
	Mode:		.BYTE 1	//Current screen
	PBDisable:	.BYTE 1	//Disable push buttons (flag)
	LastKey:	.BYTE 1	//Last key pressed on keypad

.CSEG
	//Set up interrupt vectors
	.org 0
	jmp RESET

	.org INT0ADDR
	jmp PB0Pressed

	.org INT1ADDR
	jmp PB1Pressed

	.org OVF0ADDR
	jmp T0OVF

	//.org ADCADDR (Wrong)
	//reti

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
			
			ldi ZH, high(RoundNum)
			ldi ZL, low(RoundNum)
			st Z, r16

			ldi ZH, high(Mode)
			ldi ZL, low(Mode)
			st Z, r16
			
			ldi ZH, high(PBDisable)
			ldi ZL, low(PBDisable)
			st Z, r16

			ldi ZH, high(LastKey)
			ldi ZL, low(LastKey)
			st Z, r16
			
			ldi r16, 20 //Default difficulty: easiest

			ldi ZH, high(CDTime)
			ldi ZL, low(CDTime)
			st Z, r16
			
		//Set up interrupts and timers
			//Push buttons
			ldi r16, (0b10 << ISC10) | (0b10 << ISC00) //Falling edge triggered
			sts EICRA, r16
			ldi r16, (1 << INT1) | (1 << INT0) //Unmask push button interrupts
			sts EIMSK, r16

			//Timer 0
			clr r16 //Normal timer operation
			sts TCCR0A, r16 
			ldi r16, (0b100 << CS00) //Prescaler 256
			sts TCCR0B, r16
			ldi r16, (1 << TOIE0) //Enable timer 0 overflow interrupt
			sts TIMSK0, r16

			//Timer 3
			ldi r16, (0b10 << COM3B0) | (0b01 << WGM30) //Clear on output compare match, 8-bit Fast PWM
			sts TCCR3A, r16
			ldi r16, (0b10 << WGM32) | (0b100 << CS30) //8-bit Fast PWM, Prescaler 256
			sts TCCR3B, r16
			ser r16
			sts OCR3BL, r16

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

			clr r16
			out PORTF, r16 
			out PORTA, r16
			out PORTC, r16
			out PORTG, r16
			out PORTE, r16
			
			ldi r16, 0b11101111 //Set up for reading letters only for start screen, enable pullup resistors
			sts PORTL, r16

		//Set up LCD
			do_lcd_command 0b00111000 // 2x5x7
			rcall sleep_5ms
			do_lcd_command 0b00111000 // 2x5x7
			rcall sleep_1ms
			do_lcd_command 0b00111000 // 2x5x7
			do_lcd_command 0b00111000 // 2x5x7
			do_lcd_command 0b00001000 // display off?
			do_lcd_command 0b00000001 // clear display
			do_lcd_command 0b00000110 // increment, no display shift
			do_lcd_command 0b00001110 // Cursor on, bar, no blink
		
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

		do_lcd_command 0b11000000 // shift cursor to beginning of 2nd line

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

		//Scan for letters being pressed on keypad
		ldi r16, 0b01111111
		sts PORTL, r16
		
		//Make Z point to CDTime in case difficulty is changed
		ldi ZH, high(CDTime)
		ldi ZL, low(CDTime)
		
		ScanKeypad		

	
	StartCDScreen:
		ldi ZH, high(Mode)
		ldi ZL, low(Mode)
		ldi r16, STARTCDMODE
		st Z, r16
		
	ResetPotScreen:
		ldi ZH, high(Mode)
		ldi ZL, low(Mode)
		ldi r16, RESETPOTMODE
		st Z, r16

	FindPotScreen:
		ldi ZH, high(Mode)
		ldi ZL, low(Mode)
		ldi r16, FINDPOTMODE
		st Z, r16

	FindCodeScreen:
		ldi ZH, high(Mode)
		ldi ZL, low(Mode)
		ldi r16, FINDCODEMODE
		st Z, r16

	EnterCodeScreen:
		ldi ZH, high(Mode)
		ldi ZL, low(Mode)
		ldi r16, ENTERCODEMODE
		st Z, r16

	WinScreen:
		ldi ZH, high(Mode)
		ldi ZL, low(Mode)
		ldi r16, WINMODE
		st Z, r16

	LoseScreen:
		ldi ZH, high(Mode)
		ldi ZL, low(Mode)
		ldi r16, LOSEMODE
		st Z, r16

	//Endless loop to halt operation
	LOOP:
		rjmp LOOP
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
		//cpi r22, 

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


	////////////////////////////////Interrupts////////////////////////////////
	PB0Pressed:

	reti

	PB1Pressed:

	reti
	
	T0OVF:

	reti

	T3OVF:
		push r16
		in r16, SREG
		push r16
		push ZH
		push ZL
		
		ldi ZH, high(Mode)
		ldi ZL, low(Mode)
		ld r16, Z
		
		//cpi r16, 
		
		pop ZL
		pop ZH
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
