default rel
global init_game_over_screen, process_game_over_input
extern draw_panel, write_int_right_aligned, clear_screen, draw_selection    ; utils.s
extern write_formatted_sec
extern score, lines, current_level, speed, elapsed_seconds, game_mode       ; game.s
extern panel_main                                                           ; terminal_board.s

GAME_OVER_POS_X         equ 43
GAME_OVER_POS_Y         equ 10
GAME_OVER_VALUE_LEN     equ 6

OPTIONS_PANEL_START_X   equ 20

FIRST_OPTION            equ 0
LAST_OPTION             equ 2

OPTION_RESTART          equ 0
OPTION_START            equ 1
OPTION_EXIT             equ 0

LINE_SEL_SIZE           equ 18  ; len of '[ 1 ] Restart Mode'

STATS_BUFFER_POS_X      equ 32
STATS_BUFFER_POS_Y      equ 13
STATS_MAX_LEN           equ 6

section .rodata
    ; Cursor positioning ANSI escape codes starts with (1,1) not (0,0) 
    panel_game_over:
        db 61, 24, 10, 3    ; Width, Height, X, Y
        db "                                                             ", 0   ; idx = 0
        db "             ██████   █████  ███    ███ ███████              ", 0
        db "            ██       ██   ██ ████  ████ ██                   ", 0
        db "            ██   ███ ███████ ██ ████ ██ █████                ", 0
        db "            ██    ██ ██   ██ ██  ██  ██ ██                   ", 0
        db "             ██████  ██   ██ ██      ██ ███████              ", 0
        db "                                                             ", 0
        db "             ██████  ██    ██ ███████ ███████                ", 0
        db "            ██    ██ ██    ██ ██      ██    ██               ", 0
        db "            ██    ██ ██    ██ █████   ███████                ", 0
        db "            ██    ██  ██  ██  ██      ██    ██               ", 0
        db "             ██████    ████   ███████ ██    ██               ", 0
        db "                                                             ", 0
        db "                    Stat 1:     XXXXXX                       ", 0   ; idx = 13
        db "                    Stat 2:         XX                       ", 0
        db "                    Stat 3:        XXX                       ", 0
        db "                                                             ", 0
        db "                    [ 1 ] Restart Mode                       ", 0   ; idx = 17
        db "                    [ 2 ] Start Menu                         ", 0
        db "                    [ 3 ] Exit Game                          ", 0
        db "                                                             ", 0
        db " =========================================================== ", 0
        db "    [↑/↓] Select Option  |  [SPACE] Confirm  |  [ESC] Exit   ", 0
        db "                                                             ", 0   ; idx = 23

    panel_options:
        db 61, 3, 10, 20
        db "                    [ 1 ] Restart Mode                       ", 0
        db "                    [ 2 ] Start Menu                         ", 0
        db "                    [ 3 ] Exit Game                          ", 0

    panel_stats_classic:
        db 61, 3, 10, 16
        db "                    Score:        XXXX                       ", 0
        db "                    Level:          XX                       ", 0
        db "                    Lines:         XXX                       ", 0

    panel_stats_sprint:
        db 61, 3, 10, 16
        db "                    Time:        XX:XX                       ", 0
        db "                    Level:          XX                       ", 0
        db "                    Lines:         XXX                       ", 0

    panel_stats_endless:
        db 61, 3, 10, 16
        db "                    Score:        XXXX                       ", 0
        db "                    Lines:          XX                       ", 0
        db "                    Speed:         XXX                       ", 0

    panel_stats_practice:
        db 61, 3, 10, 16
        db "                    Score:        XXXX                       ", 0
        db "                    Lines:          XX                       ", 0
        db "                    Speed:         XXX                       ", 0

    option_selector:
        dq _process_classic
        dq _process_sprint
        dq _process_endless
        dq _process_practice

section .data
    current_selection       db 0    ; Tracks active option

section .text

; =======  Entrypoint  ====================================================== ;

; Resets the current selection and processes input from the user.
; Arguments:
;   None
; Return:
;   None
init_game_over_screen:
    call clear_screen
    mov byte [current_selection], 0

    mov rdi, panel_game_over
    call draw_panel

    movzx r8d, byte [game_mode]
    mov r9, [option_selector + r8 * 8]

    movzx edi, byte [panel_game_over + 2]   ; Buffer's starting X
    movzx esi, byte [panel_game_over + 3]   ; Buffer's starting Y
    add rdi, STATS_BUFFER_POS_X             ; Terminal's starting X
    add rsi, STATS_BUFFER_POS_Y             ; Terminal's starting Y
    
    call r9

    call process_selection
    ret

; =======  Final Stats Rendering  =========================================== ;

; Renders final statistics for classic mode on the game over screen.
; Arguments:
;   rdi - X coordinate in the terminal
;   rsi - Y coordinate in the terminal
; Return:
;   None
_process_classic:
    push r15
    push r14

    mov r15, rdi
    mov r14, rsi

    mov rdi, panel_stats_classic
    call draw_panel

    mov edi, [score]
    mov rsi, STATS_MAX_LEN
    mov rdx, r15
    mov r10, r14
    call write_int_right_aligned

    movzx edi, byte [current_level]
    mov rsi, STATS_MAX_LEN
    mov rdx, r15
    mov r10, r14
    inc r10
    call write_int_right_aligned

    mov edi, [lines]
    mov rsi, STATS_MAX_LEN
    mov rdx, r15
    mov r10, r14
    add r10, 2
    call write_int_right_aligned

    pop r14
    pop r15
    ret

; Renders final statistics for sprint mode on the game over screen.
; Arguments:
;   rdi - X coordinate in the terminal
;   rsi - Y coordinate in the terminal
; Return:
;   None
_process_sprint:
    push r15
    push r14

    mov r15, rdi
    mov r14, rsi

    mov rdi, panel_stats_sprint
    call draw_panel

    movzx edi, word [elapsed_seconds]
    mov rsi, STATS_MAX_LEN
    mov rdx, r15
    mov r10, r14
    call write_formatted_sec

    movzx edi, byte [current_level]
    mov rsi, STATS_MAX_LEN
    mov rdx, r15
    mov r10, r14
    inc r10
    call write_int_right_aligned

    mov edi, [lines]
    mov rsi, STATS_MAX_LEN
    mov rdx, r15
    mov r10, r14
    add r10, 2
    call write_int_right_aligned

    pop r14
    pop r15
    ret

; Renders final statistics for endless mode on the game over screen.
; Arguments:
;   rdi - X coordinate in the terminal
;   rsi - Y coordinate in the terminal
; Return:
;   None
_process_endless:
    push r15
    push r14

    mov r15, rdi
    mov r14, rsi

    mov rdi, panel_stats_endless
    call draw_panel

    mov edi, [score]
    mov rsi, STATS_MAX_LEN
    mov rdx, r15
    mov r10, r14
    call write_int_right_aligned

    mov edi, [lines]
    mov rsi, STATS_MAX_LEN
    mov rdx, r15
    mov r10, r14
    inc r10
    call write_int_right_aligned

    movzx edi, byte [speed]
    mov rsi, STATS_MAX_LEN
    mov rdx, r15
    mov r10, r14
    add r10, 2
    call write_int_right_aligned

    pop r14
    pop r15
    ret

; Renders final statistics for practice mode on the game over screen.
; Arguments:
;   rdi - X coordinate in the terminal
;   rsi - Y coordinate in the terminal
; Return:
;   None
_process_practice:
    push r15
    push r14

    mov r15, rdi
    mov r14, rsi

    mov rdi, panel_stats_practice
    call draw_panel

    mov edi, [score]
    mov rsi, STATS_MAX_LEN
    mov rdx, r15
    mov r10, r14
    call write_int_right_aligned

    mov edi, [lines]
    mov rsi, STATS_MAX_LEN
    mov rdx, r15
    mov r10, r14
    inc r10
    call write_int_right_aligned

    movzx edi, byte [speed]
    mov rsi, STATS_MAX_LEN
    mov rdx, r15
    mov r10, r14
    add r10, 2
    call write_int_right_aligned

    pop r14
    pop r15
    ret


; =======  Input Handling  ================================================== ;

; Process all inputs from the user.
; Arguments:
;   rdi - Pointer to the input buffer
;   rsi - Length of the input
; Return:
;   rax - 0 to continue processing input, 1 to restart game, 2 to return to the
;         start menu, and -1 to quit
process_game_over_input:
    test rsi, rsi
    jz .return

    mov ecx, [rdi]      ; Load 4 bytes (even if it has garbage, we don't care yet)

    ; Route based on exact bytes read
    cmp rsi, 1
    je .handle_1_byte   ; WASD / Space
    
    cmp rsi, 3
    je .handle_3_byte   ; Arrows
    
    jmp .done         ; Ignore 2-byte or 4+-byte keystrokes

    .handle_1_byte:
        ; RSI = 1. We ONLY look at CL
        cmp cl, 'q'
        je .do_quit
        cmp cl, `\e`
        je .do_quit

        cmp cl, 0x20
        je .do_select
        cmp cl, 0x0d    ; Enter works as well
        je .do_select

        jmp .done

    .handle_3_byte:
        ; RSI = 3. Mask to 24 bits (0x00FFFFFF) to ignore the 4th LE byte
        and ecx, 0x00FFFFFF
        
        cmp ecx, `\e[A`
        je .do_up
        cmp ecx, `\e[B`
        je .do_down

        jmp .done

    .do_up:
        cmp byte [current_selection], FIRST_OPTION
        mov rdx, LAST_OPTION
        jle .apply_selection

        dec byte [current_selection]
        call process_selection

        jmp .done

    .do_down:
        cmp byte [current_selection], LAST_OPTION
        mov rdx, FIRST_OPTION
        jge .apply_selection

        inc byte [current_selection]
        call process_selection

        jmp .done

    .apply_selection:
        mov byte [current_selection], dl
        call process_selection
        jmp .done

    .do_select:
        mov rax, 1
        cmp byte [current_selection], OPTION_RESTART
        je .return

        mov rax, 2
        cmp byte [current_selection], OPTION_START
        je .return

        ; OPTION_QUIT

    .do_quit:
        mov rax, -1
        jmp .return

    .done:
        mov rax, 0

    .return:
        ret


; =======  Selector Drawing  ================================================ ;

; Updates the menu selection by redrawing the panel and highlighting the
; current choice.
; Arguments:
;   None
; Returns:
;   None
process_selection:
    ; Clear the current selection
    mov rdi, panel_options
    call draw_panel

    mov rdi, panel_options
    mov rsi, LINE_SEL_SIZE
    mov rdx, OPTIONS_PANEL_START_X
    movzx r10d, byte [current_selection]
    call draw_selection
    ret
