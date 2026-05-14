default rel
global init_start_screen, process_start_input
extern draw_panel, write_to_screen      ; utils.s

FIRST_OPTION_NO         equ 1
LAST_OPTION_NO          equ 4

; OPTIONS_CLI_START_X     equ 30
; OPTIONS_CLI_START_Y     equ 12
; Calculate CLI coords by adding panel with buffer coords
OPTIONS_PANEL_START_X   equ 20
OPTIONS_PANEL_START_Y   equ 9

LINE_SEL_SIZE           equ 21  ; len of '--- CHOOSE A MODE ---'
ANSI_INVERT_LEN         equ 4   ; Both \e[7m and \e[0m are 4 bytes
TOTAL_SEL_LEN           equ LINE_SEL_SIZE + (ANSI_INVERT_LEN * 2)

section .rodata
    ; Enter alternate buffer -> clear screen -> hide cursor
    clear_seq           db `\x1b[?1049h\x1b[2J\x1b[3J\x1b[H\x1b[?25l`
    clear_len           equ $-clear_seq

    ansi_invert_on      db `\e[7m`
    ansi_invert_off     db `\e[0m`

    ; Cursor positioning ANSI escape codes starts with (1,1) not (0,0) 
    panel_select_mode:
        db 61, 17, 10, 3    ; Width, Height, X, Y
        db "                                                             ", 0   ; idx = 0
        db "  ██████   ███████ ███    ███ ████████ ███████  ███  ███████ ", 0
        db " ██    ██ ██       ████  ████    ██    ██    ██ ███ ██       ", 0
        db " ████████ ████████ ██ ████ ██    ██    ███████  ███ ████████ ", 0
        db " ██    ██       ██ ██  ██  ██    ██    ██    ██ ███       ██ ", 0
        db " ██    ██ ████████ ██      ██    ██    ██    ██ ███ ████████ ", 0
        db "                                                             ", 0
        db "                    --- CHOOSE A MODE ---                    ", 0
        db "                                                             ", 0
        db "                    [ 1 ] Classic                            ", 0   ; idx = 9
        db "                    [ 2 ] Level Select                       ", 0
        db "                    [ 3 ] Infinite Mode                      ", 0
        db "                    [ 4 ] Zen / Practice                     ", 0
        db "                                                             ", 0
        db "                                                             ", 0
        db "                   Press a number to start                   ", 0
        db "                                                             ", 0  ; idx = 16 
         

    msg_invalid db "    Invalid Level    ", 0
    panel_level_input:
        db 25, 5, 27, 11
        db "┏━━━━━━━━━━━━━━━━━━━━━━━┓", 0
        db "┃  Enter Level (0-29):  ┃", 0
        db "┃        [    ]         ┃", 0
        db "┃  Press ENTER to play  ┃", 0
        db "┗━━━━━━━━━━━━━━━━━━━━━━━┛", 0

section .data
    current_selection       db 1    ; Tracks which option is currently active

section .text

; =======  Entrypoint  ====================================================== ;

; Setups the screen in the alternate buffer by by cleaning the screen, and
; displaying the start menu.
; Arguments:
;   None
; Return:
;   None
init_start_screen:
    ; Enter alternate buffer and clear screen
    mov rax, 1
    mov rdi, 1
    lea rsi, [clear_seq]
    mov rdx, clear_len
    syscall

    mov byte [current_selection], 1

    mov rdi, panel_select_mode
    call draw_panel

    call draw_selection

    ret

; Process all inputs from the user.
; Arguments:
;   rdi - Pointer to the input buffer
;   rsi - Length of the input
; Return:
;   rax - The mode to load, -1 on quit, or 0 otherwise
process_start_input:
    push rbp
    mov rbp, rsp

    push r15
    mov r15, 0          ; No quit

    test rsi, rsi
    jz .return

    mov ecx, [rdi]      ; Load 4 bytes (even if it has garbage, we don't care yet)

    ; Route based on exact bytes read
    cmp rsi, 1
    je .handle_1_byte   ; WASD / Space
    
    cmp rsi, 3
    je .handle_3_byte   ; Arrows
    
    jmp .return         ; Ignore 2-byte or 4+-byte keystrokes

    .handle_1_byte:
        ; RSI = 1. We ONLY look at CL
        cmp cl, 'q'
        je .do_quit
        cmp cl, 0x0D
        je .do_enter

        cmp cl, '1'
        mov rdx, 1
        je .apply_selection
        cmp cl, '2'
        mov rdx, 2
        je .apply_selection
        cmp cl, '3'
        mov rdx, 3
        je .apply_selection
        cmp cl, '4'
        mov rdx, 4
        je .apply_selection

        jmp .return

    .handle_3_byte:
        ; RSI = 3. Mask to 24 bits (0x00FFFFFF) to ignore the 4th LE byte
        and ecx, 0x00FFFFFF
        
        cmp ecx, `\e[A`
        je .do_up
        cmp ecx, `\e[B`
        je .do_down

        jmp .return

    .apply_selection:
        mov byte [current_selection], dl
        call process_selection
        jmp .return

    .do_up:
        cmp byte [current_selection], FIRST_OPTION_NO
        mov rdx, LAST_OPTION_NO
        jle .apply_selection

        dec byte [current_selection]
        call process_selection

        jmp .return

    .do_down:
        cmp byte [current_selection], LAST_OPTION_NO
        mov rdx, FIRST_OPTION_NO
        jge .apply_selection

        inc byte [current_selection]
        call process_selection

        jmp .return

    .do_quit:
        mov r15, -1
        jmp .return

    .do_enter:
        movzx r15d, byte [current_selection]
    
    .return:
        mov rax, r15

        pop r15
        leave
        ret

; TODO
process_selection:
    ; Clear the current selection
    mov rdi, panel_select_mode
    call draw_panel

    call draw_selection
    ret

; TODO
draw_selection:
    push rbp
    mov rbp, rsp

    sub rsp, TOTAL_SEL_LEN

    lea r8, [panel_select_mode + 4]     ; src ptr
    mov r9, rsp                         ; dst ptr

    mov eax, dword [ansi_invert_on]
    mov dword [r9], eax

    add r9, ANSI_INVERT_LEN

    movzx r10d, byte [current_selection]
    dec r10                                 ; Mode starts at 1, offset at 0
    add r10, OPTIONS_PANEL_START_Y          ; Target row
    mov r11, r10
    
    ; We are using multi-byte utf-8 chars, we need a loop
    .find_start_of_selection:
        .traverse_row:
            inc r8
            cmp byte [r8], 0
            jnz .traverse_row

        dec r10
        jnz .find_start_of_selection

    inc r8                          ; At selection's row
    add r8, OPTIONS_PANEL_START_X
    
    mov rsi, r8
    mov rdi, r9
    mov rcx, LINE_SEL_SIZE
    rep movsb                       ; rdi now points to the end of the copied string

    mov r9, rdi

    mov eax, dword [ansi_invert_off]
    mov dword [r9], eax
    
    add r9, ANSI_INVERT_LEN

    mov rdi, rsp                    ; arg 1: buffer pointer

    mov rsi, r9
    sub rsi, rsp                    ; arg 2: length = end_ptr - start_ptr (should be TOTAL_SEL_LEN)

    mov rdx, OPTIONS_PANEL_START_X  ; arg 3: X
    add dl, byte [panel_select_mode + 2]
    mov r10, r11                    ; arg 3: Y
    add r10b, byte [panel_select_mode + 3]
    call write_to_screen

    leave
    ret


; LAST THING, TERMINAL IS STUCK ON THE SELECTION