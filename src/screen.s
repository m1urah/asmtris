global setup_board
extern write_to_screen, strlen
default rel

section .rodata
    ;# Enter alternate buffer -> clear screen -> hide cursor
    clear_seq           db `\x1b[?1049h\x1b[2J\x1b[3J\x1b[H\x1b[?25l`
    clear_len           equ $-clear_seq

    hello_world         db "Hello, World 1!"
    hello_world_len     equ $-hello_world
    hello_world_2       db "Hello, World 2!"
    hello_world_3       db "Hello, World 3!"

    ;# === PANELS ===
    ; Cursor positioning ANSI escape codes starts with (1,1) not (0,0) 
    panel_stats:
        db 5    ; height
        db 1    ; col (X)
        db 1    ; line(Y)
        ; utf-8 chars are multi-byte, null terminator marks end of row
        db "┏━━━━━━━Stats━━━━━━━┓", 0
        db "┃ Score       10420 ┃", 0
        db "┃ Level           5 ┃", 0
        db "┃ Lines          42 ┃", 0
        db "┗━━━━━━━━━━━━━━━━━━━┛", 0

    panel_next:
        db 5
        db 56
        db 1
        db "┏━━━━━━━Next━━━━━━━┓", 0
        db "┃                  ┃", 0
        db "┃     ████████     ┃", 0
        db "┃                  ┃", 0
        db "┗━━━━━━━━━━━━━━━━━━┛", 0

    panel_help:
        db 8
        db 56
        db 8
        db "┏━━━━━━━Help━━━━━━━┓", 0
        db "┃ Left      h, ←   ┃", 0
        db "┃ Right     l, →   ┃", 0
        db "┃ Down      j, ↓   ┃", 0
        db "┃ Rotate    k, ↑   ┃", 0
        db "┃ Drop      space  ┃", 0
        db "┃ Quit      q      ┃", 0
        db "┗━━━━━━━━━━━━━━━━━━┛", 0

    panel_main:
        db 22
        db 25
        db 1
        db "┏━━━━━━━━━━━Tetris━━━━━━━━━━━┓", 0
        db "┃                            ┃", 0  ;# Row 20 (Top)
        db "┃                            ┃", 0
        db "┃                            ┃", 0
        db "┃                            ┃", 0
        db "┃                            ┃", 0
        db "┃                            ┃", 0
        db "┃                            ┃", 0
        db "┃                            ┃", 0
        db "┃                            ┃", 0
        db "┃                            ┃", 0
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

; Entrypoint for the screen module. Setups the board in the alternate buffer by
; cleaning the screen, and placing all panels.
; Arguments:
;   None
; Return:
;   None
setup_board:
    ; Enter alternate buffer and clear screen
    mov rax, 1
    mov rdi, 1
    lea rsi, [clear_seq]
    mov rdx, clear_len
    syscall

    mov rdi, panel_stats
    call _draw_panel

    mov rdi, panel_next
    call _draw_panel

    mov rdi, panel_help
    call _draw_panel

    mov rdi, panel_main
    call _draw_panel

    ret


; =======  Helpers  ======================================================== #

; Draws a given panel (multi-line elem) on the screen at (X,Y), where (1,1) is
; the top-left corner. Renders each line of the panel STARTING at the
; specified coordinates.
; Arguments:
;   rdi - Pointer to panel data: first 3 bytes are metadata (height, x-offset, 
;         y-offset), followed by height null-terminated string rows
; Return:
;   rax - Success (0) or error (-1)
_draw_panel:
    ; === PROLOGUE ===
    push r15
    push r14
    push r13
    push r12

    xor r12, r12
    xor r13, r13
    xor r14, r14
    xor r15, r15

    mov r12b, byte [rdi]        ; height
    mov r13b, byte [rdi+1]      ; col (X)
    mov r14b, byte [rdi+2]      ; line (Y)
    add r12b, r14b              ; end_Y = height + starting line (Y)
    lea r15, [rdi+3]            ; data
    
    .print_lines:
        mov rdi, r15
        mov rsi, 1024
        call strlen

        cmp rax, 1024
        je .error

        mov rdi, r15
        mov rsi, rax
        mov rdx, r13
        mov r10, r14
        call write_to_screen

        lea r15, [r15+rax+1]    ; next line
        inc r14

        cmp r14, r12
        jb .print_lines         ; not all lines printed?

    mov rax, 0
    jmp .return

    .error:
        mov rax, 1

    .return:
        pop r12
        pop r13
        pop r14
        pop r15
        pop rbp

        ret
