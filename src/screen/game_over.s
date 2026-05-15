default rel
global render_game_over
extern draw_panel, write_int_right_aligned   ; utils.s
extern score, lines, level                  ; board.s
extern panel_main                           ; terminal_board.s

GAME_OVER_POS_X         equ 43
GAME_OVER_POS_Y         equ 10
GAME_OVER_VALUE_LEN     equ 6

section .rodata
    ; Cursor positioning ANSI escape codes starts with (1,1) not (0,0) 
    panel_game_over:
        db 30, 10, 24, 7    ; Width, Height, X, Y
        db "┃     G A M E    O V E R     ┃", 0
        db "┃    ════════════════════    ┃", 0
        db "┃                            ┃", 0
        db "┃    Final Score:       X    ┃", 0
        db "┃    Lines Cleared:     X    ┃", 0
        db "┃    Level Reached:     X    ┃", 0
        db "┃                            ┃", 0
        db "┃                            ┃", 0
        db "┃       Press [Space]        ┃", 0
        db "┃       to play again.       ┃", 0


section .text

; =======  Game Over Rendering  ============================================= ;

; Renders the Game Over screen with the final game statistics.
; Arguments:
;   None
; Return:
;   None
render_game_over:
    ; Clean the main panel
    mov rdi, panel_main
    call draw_panel

    mov rdi, panel_game_over
    call draw_panel

    mov edi, [score]
    mov rsi, GAME_OVER_VALUE_LEN
    mov rdx, GAME_OVER_POS_X
    mov r10, GAME_OVER_POS_Y
    call write_int_right_aligned

    mov edi, [lines]
    mov rsi, GAME_OVER_VALUE_LEN
    mov rdx, GAME_OVER_POS_X
    mov r10, GAME_OVER_POS_Y
    add r10, 1
    call write_int_right_aligned

    movzx edi, byte [level]
    mov rsi, GAME_OVER_VALUE_LEN
    mov rdx, GAME_OVER_POS_X
    mov r10, GAME_OVER_POS_Y
    add r10, 2
    call write_int_right_aligned

    ret
