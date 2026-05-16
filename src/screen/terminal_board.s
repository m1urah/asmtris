default rel
global init_board_screen, update_screen, panel_main
extern MODE_CLASSIC, MODE_SPRINT, MODE_ENDLESS, MODE_PRACTICE                   ; screen/start.s
extern draw_panel, write_to_screen, itoa, render_buffer_colored                 ; utils.s
extern write_to_screen, write_int_right_aligned, write_str_left_aligned     
extern write_formatted_sec, clear_screen
extern game_board, next_piece, score, lines, current_level, next_level, speed   ; game.s
extern lines_left, elapsed_seconds, game_mode, needs_next_piece_redraw
extern is_paused, game_over_off, GAME_BOARD_WIDTH, NUMBER_OF_HIDDEN_ROWS

TERMINAL_BOARD_WIDTH    equ 26
TERMINAL_BOARD_HEIGHT   equ 21
TERMINAL_BOARD_INIT_X   equ 26
TERMINAL_BOARD_INIT_Y   equ 2

STATS_POS_X             equ 13
STATS_POS_Y             equ 9
STATS_VALUE_LEN         equ 6   ; Max chars per stat

NEXT_PIECE_POS_Y        equ 3
NEXT_PIECE_POS_Y_I      equ 2   ; I is 4 rows long, would overflow
NEXT_PIECE_POS_X        equ 8
NEXT_PIECE_POS_X_I      equ 7
NEXT_PIECE_POS_X_O      equ 9

section .rodata
    on_str              db 'ON', 0
    off_str             db 'OFF', 0

    ; Cursor positioning ANSI escape codes starts with (1,1) not (0,0) 
    panel_stats_classic:
        db 20   ; width
        db 6    ; height
        db 1    ; col (X)
        db 8    ; line (Y)
        ; utf-8 chars are multi-byte, null terminator marks end of row
        db "┏━━━━━━━Stats━━━━━━┓", 0
        db "┃ Score          X ┃", 0
        db "┃ Level          X ┃", 0
        db "┃ Lines          X ┃", 0
        db "┃ Next Level     X ┃", 0
        db "┗━━━━━━━━━━━━━━━━━━┛", 0

    panel_stats_sprint:
        db 20, 6, 1, 8
        db "┏━━━━━━━Stats━━━━━━┓", 0
        db "┃ Time       XX:XX ┃", 0
        db "┃ Level          X ┃", 0
        db "┃ Lines          X ┃", 0
        db "┃ Lines Left     X ┃", 0
        db "┗━━━━━━━━━━━━━━━━━━┛", 0

    panel_stats_endless:
        db 20, 5, 1, 8
        db "┏━━━━━━━Stats━━━━━━┓", 0
        db "┃ Score          X ┃", 0
        db "┃ Lines          X ┃", 0
        db "┃ Speed          X ┃", 0
        db "┗━━━━━━━━━━━━━━━━━━┛", 0

    panel_stats_practice:
        db 20, 6, 1, 8
        db "┏━━━━━━━Stats━━━━━━┓", 0
        db "┃ Score          X ┃", 0
        db "┃ Lines          X ┃", 0
        db "┃ Speed          X ┃", 0
        db "┃ Game Over      X ┃", 0
        db "┗━━━━━━━━━━━━━━━━━━┛", 0

    panel_stats_selector:
        dq panel_stats_classic
        dq panel_stats_sprint
        dq panel_stats_endless
        dq panel_stats_practice

    panel_next:
        db 20, 6, 1, 1
        db "┏━━━━━━━Next━━━━━━━┓", 0
        db "┃                  ┃", 0
        db "┃       ????       ┃", 0
        db "┃       ????       ┃", 0
        db "┃                  ┃", 0
        db "┗━━━━━━━━━━━━━━━━━━┛", 0

    panel_help:
        db 20, 9, 1, 15
        db "┏━━━━━━━Help━━━━━━━┓", 0
        db "┃ Left      h, ←   ┃", 0
        db "┃ Right     l, →   ┃", 0
        db "┃ Down      j, ↓   ┃", 0
        db "┃ Rotate    k, ↑   ┃", 0
        db "┃ Drop      space  ┃", 0
        db "┃ Quit      q      ┃", 0
        db "┃ Pause     p, ESC ┃", 0
        db "┗━━━━━━━━━━━━━━━━━━┛", 0

    panel_main:
        db 30, 23, 24, 1
        db "┏━━━━allthingsmalware.com━━━━┓", 0
        db "┃                            ┃", 0  ;# Row 21 (Top)
        db "┃                            ┃", 0
        db "┃                            ┃", 0
        db "┃                            ┃", 0
        db "┃                            ┃", 0
        db "┃                            ┃", 0
        db "┃                            ┃", 0
        db "┃                            ┃", 0 
        db "┃                            ┃", 0
        db "┃         [ PAUSED ]         ┃", 0
        db "┃      press p to resume     ┃", 0
        db "┃                            ┃", 0
        db "┃                            ┃", 0 
        db "┃                            ┃", 0 
        db "┃                            ┃", 0 
        db "┃                            ┃", 0 
        db "┃                            ┃", 0 
        db "┃                            ┃", 0 
        db "┃                            ┃", 0 
        db "┃                            ┃", 0 
        db "┃                            ┃", 0  ;# Row 1 (Bottom)
        db "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛", 0


section .text

; Setups the board and all panels.
; Arguments:
;   None
; Return:
;   None
init_board_screen:
    call clear_screen

    movzx r8, byte [game_mode]
    lea r9, [panel_stats_selector]  ; RIP-relative addressing
    mov rdi, [r9 + r8 * 8]          ; src index
    call draw_panel

    mov rdi, panel_next
    call draw_panel

    mov rdi, panel_help
    call draw_panel

    mov rdi, panel_main
    call draw_panel

    call update_screen      ; Wipes pause panel immediately to prevent visual "flash"
    ret


; =======  Board Rendering  ================================================= ;

; Clear the previous frame and update the screen with the latest game state,
; including the game board, current score, lines cleared, and current level.
; Arguments:
;   None
; Return:
;   None
update_screen:
    cmp byte [is_paused], 1
    je .display_paused_graphics

    call _print_board
    call update_stats

    cmp byte [needs_next_piece_redraw], 1
    jnz .return

    ; If dirty, redraw and clean the flag
    call _set_next_piece
    mov byte [needs_next_piece_redraw], 0

    jmp .return

    .display_paused_graphics:
        mov rdi, panel_next
        call draw_panel

        mov rdi, panel_help
        call draw_panel

        mov rdi, panel_main
        call draw_panel

    .return:
        ret

; Translates the 1D logical game board array into characters and renders them
; to the screen. To scale the visual output, each byte from the buffer is
; duplicated horizontally when rendered.
; Arguments:
;   None
; Return:
;   None
_print_board:
    push r15
    push r14
    push r13
    push r12

    mov r15, TERMINAL_BOARD_INIT_X      ; Initial X
    mov r14, TERMINAL_BOARD_INIT_Y      ; Initial Y
    
    mov r13, r14
    add r13, TERMINAL_BOARD_HEIGHT      ; End Y = Y + height

    ; Calculate start of game_board's visible zone (first N lines are hidden)
    mov rax, GAME_BOARD_WIDTH
    imul rax, rax, NUMBER_OF_HIDDEN_ROWS

    lea r12, [game_board]
    lea r12, [r12 + rax]                ; src ptr

    .print_next_line:
        cmp r14, r13
        jae .return

        mov rdi, r12
        mov rsi, GAME_BOARD_WIDTH
        mov rdx, r15
        mov r10, r14
        call render_buffer_colored

        ; Next line
        inc r14
        lea r12, [r12 + rax]

        jmp .print_next_line

    .return:
        pop r12
        pop r13
        pop r14
        pop r15
        ret


; =======  Stats Panel  ===================================================== ;

; Updates the stats panel based on the current game mode.
; Arguments:
;   None
; Return:
;   None
update_stats:
    movzx r8d, byte [game_mode]
    
    cmp r8, MODE_CLASSIC
    je .classic

    cmp r8, MODE_SPRINT
    je .sprint

    cmp r8, MODE_ENDLESS
    je .endless

    jmp .practice

    .classic:
        mov edi, dword [score]
        mov rsi, 0
        call _set_int_stat

        movzx edi, byte [current_level]
        mov rsi, 1
        call _set_int_stat

        mov edi, dword [lines]
        mov rsi, 2
        call _set_int_stat

        mov rsi, 3

        movzx edi, byte [next_level]
        cmp dil, byte [current_level]
        jne .int_level

        ; If levels are equals means there's no next level
        .str_level:
            sub rsp, 2
            mov byte [rsp], '-'
            mov byte [rsp + 1], 0
            
            mov rdi, rsp
            call _set_str_stat

            add rsp, 2
            jmp .return

        .int_level:
            call _set_int_stat
            jmp .return

    .sprint:
        movzx edi, word [elapsed_seconds]
        mov rsi, STATS_VALUE_LEN
        mov rdx, STATS_POS_X
        mov r10, STATS_POS_Y
        call write_formatted_sec

        movzx edi, byte [current_level]
        mov rsi, 1
        call _set_int_stat

        mov edi, dword [lines]
        mov rsi, 2
        call _set_int_stat

        movzx edi, byte [lines_left]
        mov rsi, 3
        call _set_int_stat

        jmp .return

    .endless:
        mov edi, dword [score]
        mov rsi, 0
        call _set_int_stat

        mov edi, dword [lines]
        mov rsi, 1
        call _set_int_stat

        movzx edi, byte [speed]
        mov rsi, 2
        call _set_int_stat

        jmp .return

    .practice:
        mov edi, dword [score]
        mov rsi, 0
        call _set_int_stat

        mov edi, dword [lines]
        mov rsi, 1
        call _set_int_stat

        movzx edi, byte [speed]
        mov rsi, 2
        call _set_int_stat

        mov rdi, on_str
        cmp byte [game_over_off], 0
        je .set_game_over

        mov rdi, off_str
        
        .set_game_over:
            mov rsi, 3
            call _set_str_stat
    
    .return:
        ret

; Renders a specific INT stat to the stats panel.
; Arguments:
;   rdi - Stat value
;   rsi - Y offset relative to STATS_POS_Y
; Return:
;   None
_set_int_stat:
    mov r8, rsi

    ; rdi already set
    mov rsi, STATS_VALUE_LEN
    mov rdx, STATS_POS_X
    mov r10, STATS_POS_Y
    add r10, r8
    call write_int_right_aligned

    ret

; Renders a specific STRING stat to the stats panel.
; Arguments:
;   rdi - Stat value pointer
;   rsi - Y offset relative to STATS_POS_Y
; Return:
;   None
_set_str_stat:
    mov r8, rsi

    ; rdi already set
    mov rsi, STATS_VALUE_LEN
    mov rdx, STATS_POS_X
    mov r10, STATS_POS_Y
    add r10, r8
    call write_str_left_aligned

    ret


; ======= Next Piece Panel  ================================================= ;

; Renders the next piece in the "Next" panel. Clears the previous piece and
; draws the new one centered based on its dimensions.
; Arguments:
;   None
; Return:
;   None
_set_next_piece:
    cmp byte [next_piece + 1], 0
    jz .return

    movzx r8d, byte [next_piece + 1]
    cmp [next_piece], r8b
    jne .return

    ; --- Height != 0 and Height == Width ---
    
    push rbp
    mov rbp, rsp

    push r15
    push r14
    push r13
    push r12
    push rbx

    call _clear_next_piece_panel

    lea r15, [next_piece + 7]       ; Figure array ptr
    movzx r14d, byte [next_piece]   ; X counter
    mov r13, r14                    ; Y counter

    sub rsp, r13

    ; Set special X, Y for i piece
    mov r12, NEXT_PIECE_POS_X_I
    mov rbx, NEXT_PIECE_POS_Y_I
    cmp r14, 4
    je .render_next_row

    ; Set special X for o piece, Y for the rest
    mov r12, NEXT_PIECE_POS_X_O
    mov rbx, NEXT_PIECE_POS_Y
    cmp r14, 2
    je .render_next_row

    ; Set special X for the rest
    mov r12, NEXT_PIECE_POS_X

    .render_next_row:
        mov rcx, r14
        mov rdx, rsp

        .render_row:
            movzx r8d, byte [next_piece + 5]
            mov r9, 0x20
            cmp byte [r15], 1
            cmovne r8, r9       ; If 0 -> 0x20, if 1 -> piece color

            mov [rdx], r8

            inc rdx
            inc r15
            dec rcx
            jnz .render_row

    .render_next_row_end:
        mov rdi, rsp
        mov rsi, r14
        mov rdx, r12
        mov r10, rbx
        call render_buffer_colored 

        inc rbx     ; Next line
        dec r13
        jnz .render_next_row

    pop rbx
    pop r12
    pop r13
    pop r14
    pop r15

    leave

    .return:
        ret

; Prepares the Next panel by removing the previous piece.
; Arguments:
;   None
; Return:
;   None
_clear_next_piece_panel:
    push r15
    push r14
    push r13
    push r12
    push rbx

    ; Remove left/right top/bottom delimiters
    movzx r15d, byte [panel_next]       ; Width
    sub r15, 2
    movzx r14d, byte [panel_next + 1]   ; Height
    sub r14, 2

    ; Set coordinates after delimiters
    movzx r13d, byte [panel_next + 2]   ; X
    inc r13
    movzx r12d, byte [panel_next + 3]   ; Y
    inc r12

    sub rsp, r15

    ; Create clear str
    mov rax, 0x20
    mov rdi, rsp
    mov rcx, r15
    rep stosb

    .write_clear_str:
        mov rdi, rsp
        mov rsi, r15
        mov rdx, r13
        mov r10, r12
        call write_to_screen

        inc r12
        dec r14
        jnz .write_clear_str

    add rsp, r15

    pop rbx
    pop r12
    pop r13
    pop r14
    pop r15
    ret
