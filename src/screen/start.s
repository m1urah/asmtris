default rel
global init_start_screen, process_start_input
extern MODE_CLASSIC, MODE_SPRINT, MODE_ENDLESS, MODE_PRACTICE, FIRST_LEVEL      ; common.s
extern MAX_SELECTABLE_LEVEL, MAX_LEVEL_CHAR_LEN
extern draw_panel, write_to_screen, write_int_right_aligned, draw_selection     ; utils.s
extern clear_screen, ANSI_INVERT_LEN
extern start_level, game_over_off, game_mode                                    ; game.s

FIRST_OPTION            equ 0
LAST_OPTION             equ 3

OPTIONS_PANEL_START_X   equ 20
OPTIONS_PANEL_START_Y   equ 9

LEVEL_SELECTOR_START_X  equ 39
LEVEL_SELECTOR_START_Y  equ 13

LINE_SEL_SIZE           equ 21  ; len of '--- CHOOSE A MODE ---'

section .rodata
    ansi_invert_on      db `\e[7m`
    ansi_invert_off     db `\e[0m`

    ; Cursor positioning ANSI escape codes starts with (1,1) not (0,0) 
    panel_select_mode:
        db 61, 18, 10, 3    ; Width, Height, X, Y
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
        db "                    [ 2 ] Sprint                             ", 0
        db "                    [ 3 ] Endless                            ", 0
        db "                    [ 4 ] Zen / Practice                     ", 0
        db "                                                             ", 0
        db "                                                             ", 0
        db " =========================================================== ", 0
        db "     [↑/↓] Change Mode  |  [SPACE] Confirm  |  [ESC] Exit    ", 0
        db "                                                             ", 0   ; idx = 19

    panel_classic_mode:
        db 61, 10, 10, 10
        db "                    --- CLASSIC MODE ---                     ", 0
        db "                                                             ", 0
        db "                     Select Start Level                      ", 0
        db "                    <      [  0 ]      >                     ", 0
        db "                                                             ", 0
        db "                                                             ", 0
        db "                                                             ", 0
        db "                                                             ", 0
        db " =========================================================== ", 0
        db "    [←/→] Change Level  |  [SPACE] Confirm  |  [ESC] Exit    ", 0

    panel_sprint_mode:
        db 61, 10, 10, 10
        db "                    --- SPRINT MODE ---                      ", 0
        db "                                                             ", 0
        db "                        Select Level                         ", 0
        db "                    <      [  0 ]      >                     ", 0
        db "                                                             ", 0
        db "                                                             ", 0
        db "                                                             ", 0
        db "                                                             ", 0
        db " =========================================================== ", 0
        db "    [←/→] Change Level  |  [SPACE] Confirm  |  [ESC] Exit    ", 0

    panel_endless_mode:
        db 61, 10, 10, 10
        db "                    --- ENDLESS MODE ---                     ", 0
        db "                                                             ", 0
        db "                       Ready to drop?                        ", 0
        db "                        (No limits!)                         ", 0
        db "                                                             ", 0
        db "                                                             ", 0
        db "                                                             ", 0
        db "                                                             ", 0
        db " =========================================================== ", 0
        db "               [SPACE] Confirm  |  [ESC] Exit                ", 0

    panel_practice_mode:
        db 61, 10, 10, 10
        db "                    --- PRACTICE MODE ---                    ", 0
        db "                                                             ", 0
        db "                     Select Start Level                      ", 0
        db "                    <      [  0 ]      >                     ", 0
        db "                                                             ", 0
        db "                                                             ", 0
        db "                    [ ] Disable Game Over                    ", 0
        db "                                                             ", 0
        db " =========================================================== ", 0
        db "     [←/→/ENTER] Options | [SPACE] Confirm | [ESC] Exit      ", 0

    panel_practice_yes:
        db 61, 1, 10, 16
        db "                    [X] Disable Game Over                    ", 0

    panel_practice_no:
        db 61, 1, 10, 16
        db "                    [ ] Disable Game Over                    ", 0

    panel_selector:
        dq panel_classic_mode
        dq panel_sprint_mode
        dq panel_endless_mode
        dq panel_practice_mode

    ; When on the 2nd screen
    mode_selector:
        dq _process_classic
        dq _process_sprint
        dq _process_endless
        dq _process_practice

section .data
    current_selection       db 0    ; Tracks active option (0 = Classic, 1 = Sprint, etc.)
    in_mode_screen          db 0

section .text

; =======  Entrypoint  ====================================================== ;

; Resets the current selection and processes input from the user.
; Arguments:
;   None
; Return:
;   None
init_start_screen:
    call clear_screen
    mov byte [current_selection], 0
    mov byte [in_mode_screen], 0

    mov byte [start_level], 0
    mov byte [game_over_off], 0

    call process_selection
    ret


; =======  Input Handling  ================================================== ;

; Process all inputs from the user.
; Arguments:
;   rdi - Pointer to the input buffer
;   rsi - Length of the input
; Return:
;   rax - 0 to continue processing input, 1 to start game, and -1 to quit
process_start_input:
    test rsi, rsi
    jz .return

    ; Route based on current screen
    cmp byte [in_mode_screen], 0
    je .main_screen

    call _process_mode_screen
    jmp .return

    .main_screen:
        call _process_main_screen

    .return:
        ret

; Process main screen input.
; Arguments:
;   rdi - Pointer to the input buffer
;   rsi - Length of the input
; Return:
;   rax - -1 to quit, or 0 otherwise
_process_main_screen:
    mov ecx, [rdi]      ; Load 4 bytes (even if it has garbage, we don't care yet)

    ; Route based on exact bytes read
    cmp rsi, 1
    je .handle_1_byte   ; WASD / Space
    
    cmp rsi, 3
    je .handle_3_byte   ; Arrows
    
    jmp .done           ; Ignore 2-byte or 4+-byte keystrokes

    .handle_1_byte:
        ; RSI = 1. We ONLY look at CL
        cmp cl, 'q'
        je .do_quit
        cmp cl, `\e`
        je .do_quit

        cmp cl, 0x20
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

    .do_quit:
        mov rax, -1
        jmp .return

    .do_select:
        movzx r8d, byte [current_selection]
        mov byte [in_mode_screen], 1

        mov rdi, [panel_selector + r8 * 8]
        call draw_panel
    
    .done:
        mov rax, 0

    .return:
        ret

; Process mode screen input. Returns the mode to load when the user indicates
; that is ready to play. 
; Arguments:
;   rdi - Pointer to the input buffer
;   rsi - Length of the input
; Return:
;   rax - 0 to continue processing input, 1 to start game, and -1 to quit
_process_mode_screen:
    mov ecx, [rdi]      ; Load 4 bytes (even if it has garbage, we don't care yet)

    push rbp
    mov rbp, rsp

    push r15
    mov r15, 0          ; No quit

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
        cmp cl, `\e`
        je .do_quit

        cmp cl, 0x7f
        je .do_return
        cmp cl, 0x20
        je .do_confirm

        cmp cl, 0x0d
        je .call_processing_function

        jmp .return

    .handle_3_byte:
        ; RSI = 3. Mask to 24 bits (0x00FFFFFF) to ignore the 4th LE byte
        and ecx, 0x00FFFFFF

    .call_processing_function:
        movzx rbx, byte [current_selection]

        ; Jump to the correct toggle processing function
        mov r8, [mode_selector + rbx * 8]
        mov rdi, rcx
        call r8

        jmp .return

    .do_quit:
        mov r15, -1
        jmp .return

    .do_return:
        mov byte [in_mode_screen], 0

        call process_selection
        jmp .return

    .do_confirm:
        movzx r8d, byte [current_selection]
        mov byte [game_mode], r8b
        mov r15, 1      ; Start game

    .return:
        mov rax, r15

        pop r15
        leave
        ret


; =======  Mode Screen Toggle  ============================================== ;

; Process input for the classic mode configuration screen.
; Arguments:
;   rdi - Input sequence from the user
; Return:
;   None
_process_classic:
    call _level_toggle
    ret

; Process input for the sprint mode configuration screen.
; Arguments:
;   rdi - Input sequence from the user
; Return:
;   None
_process_sprint:
    call _level_toggle
    ret

; Process left and right arrow input to toggle the selected start level.
; Arguments:
;   rdi - Input sequence from the user
; Return:
;   None
_level_toggle:
    mov rcx, rdi

    cmp ecx, `\e[D`
    je .do_left
    cmp ecx, `\e[C`
    je .do_right

    jmp .return

    .do_left:
        cmp byte [start_level], FIRST_LEVEL
        mov rdx, MAX_SELECTABLE_LEVEL
        jle .apply_level
        
        movzx edx, byte [start_level]
        dec rdx
        jmp .apply_level

    .do_right:
        cmp byte [start_level], MAX_SELECTABLE_LEVEL
        mov rdx, FIRST_LEVEL
        jge .apply_level

        movzx edx, byte [start_level]
        inc rdx

    .apply_level:
        mov byte [start_level], dl

        mov rdi, rdx
        mov rsi, MAX_LEVEL_CHAR_LEN
        mov rdx, LEVEL_SELECTOR_START_X
        mov r10, LEVEL_SELECTOR_START_Y
        call write_int_right_aligned

    .return:
        ret

; Process input for the practice mode configuration screen.
; Arguments:
;   rdi - Input sequence from the user
; Return:
;   None
_process_practice:
    mov rcx, rdi

    cmp ecx, `\e[D`
    je .toggle_level
    cmp ecx, `\e[C`
    je .toggle_level

    cmp cl, 0x0d    ; Enter
    je .toggle_game_over

    jmp .return

    .toggle_level:
        call _level_toggle
        jmp .return

    .toggle_game_over:
        xor byte [game_over_off], 1
        
        mov rdi, panel_practice_no
        cmp byte [game_over_off], 0
        je .paint_option

        mov rdi, panel_practice_yes

    .paint_option:
        call draw_panel

    .return:
        ret

; Process input for the endless mode configuration screen.
; Arguments:
;   rdi - Input sequence from the user
; Return:
;   None
_process_endless:
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
    mov rdi, panel_select_mode
    call draw_panel

    mov rdi, panel_select_mode
    mov rsi, LINE_SEL_SIZE
    mov rdx, OPTIONS_PANEL_START_X
    movzx r10d, byte [current_selection]
    add r10, OPTIONS_PANEL_START_Y  ; Target row
    call draw_selection

    ret
