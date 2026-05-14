default rel
global init_board_screen, update_screen, panel_main
extern draw_panel, write_to_screen, itoa, render_buffer_colored         ; utils.s
extern write_int_left_aligned, write_to_screen     
extern game_board, next_piece, score, lines, level, is_paused           ; board.s
extern needs_next_piece_redraw, GAME_BOARD_WIDTH, NUMBER_OF_HIDDEN_ROWS

TERMINAL_BOARD_WIDTH    equ 26
TERMINAL_BOARD_HEIGHT   equ 21
TERMINAL_BOARD_INIT_X   equ 26
TERMINAL_BOARD_INIT_Y   equ 2

STATS_STAT_POS_X        equ 13  ; Max 6 chars per stat
STATS_STAT_POS_Y        equ 10
STATS_VALUE_LEN         equ 6

NEXT_PIECE_POS_Y        equ 3
NEXT_PIECE_POS_Y_I      equ 2   ; I is 4 rows long, would overflow
NEXT_PIECE_POS_X        equ 8
NEXT_PIECE_POS_X_I      equ 7
NEXT_PIECE_POS_X_O      equ 9

section .rodata
    clear_seq           db `\x1b[2J`
    clear_len           equ $-clear_seq

    ; Cursor positioning ANSI escape codes starts with (1,1) not (0,0) 
    panel_stats:
        db 20   ; width
        db 6    ; height
        db 1    ; col (X)
        db 8    ; line (Y)
        ; utf-8 chars are multi-byte, null terminator marks end of row
        db "┏━━━━━━━Stats━━━━━━┓", 0
        db "┃ Top            X ┃", 0
        db "┃ Score          X ┃", 0
        db "┃ Lines          X ┃", 0
        db "┃ Level          X ┃", 0
        db "┗━━━━━━━━━━━━━━━━━━┛", 0

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
    ; Clear screen
    mov rax, 1
    mov rdi, 1
    lea rsi, [clear_seq]
    mov rdx, clear_len
    syscall

    mov rdi, panel_stats
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
    call _set_score
    call _set_level
    call _set_lines

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


; =======  Panel Rendering  ================================================= ;

; Renders the current game score to its designated place on the screen.
; Arguments:
;   None
; Return:
;   None
_set_score:
    mov edi, dword [score]
    mov rsi, STATS_VALUE_LEN
    mov rdx, STATS_STAT_POS_X
    mov r10, STATS_STAT_POS_Y
    call write_int_left_aligned

    ret

; Renders the number of cleared lines to its designated place on the screen.
; Arguments:
;   None
; Return:
;   None
_set_lines:
    mov edi, dword [lines]
    mov rsi, STATS_VALUE_LEN
    mov rdx, STATS_STAT_POS_X
    mov r10, STATS_STAT_POS_Y
    add r10, 1
    call write_int_left_aligned

    ret

; Renders the current level to its designated place on the screen.
; Arguments:
;   None
; Return:
;   None
_set_level:
    movzx edi, byte [level]
    mov rsi, STATS_VALUE_LEN
    mov rdx, STATS_STAT_POS_X
    mov r10, STATS_STAT_POS_Y
    add r10, 2
    call write_int_left_aligned

    ret

; Renders the next piece to the screen.
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
