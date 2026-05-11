global init_screen, update_screen, render_game_over
extern GAME_BOARD_WIDTH, NUMBER_OF_HIDDEN_ROWS
extern game_board, score, level, lines, next_piece, needs_next_piece_redraw, is_paused
default rel

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

GAME_OVER_POS_X         equ 43
GAME_OVER_POS_Y         equ 10
GAME_OVER_VALUE_LEN     equ 6

MAX_COLOR_ESC_SEQ_SIZE  equ 17  ; Counting two spaces

section .rodata
    ; Enter alternate buffer -> clear screen -> hide cursor
    clear_seq           db `\x1b[?1049h\x1b[2J\x1b[3J\x1b[H\x1b[?25l`
    clear_len           equ $-clear_seq

    ; === PANELS ===
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

    panel_game_over:
        db 30, 10, 24, 7
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

    ; === COLORS ===
    color_prefix_seq            db `\e[48;5;`   ; Background (for visible spaces)
    color_prefix_seq_len        equ $-color_prefix_seq
    color_after_code_seq        db `m`
    color_after_code_seq_len    equ $-color_after_code_seq
    color_suffix_seq            db `\e[0m`
    color_suffix_seq_len        equ $-color_suffix_seq

section .text

; =======  Board Initialization  ============================================ ;

; Setups the board in the alternate buffer by cleaning the screen,
; and placing all initial panels.
; Arguments:
;   None
; Return:
;   None
init_screen:
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

    call update_screen      ; Wipes pause panel immediately to prevent visual "flash"
    ret

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

    mov r12b, byte [rdi+1]      ; height
    mov r13b, byte [rdi+2]      ; col (X)
    mov r14b, byte [rdi+3]      ; line (Y)
    add r12b, r14b              ; end_Y = height + starting line (Y)
    lea r15, [rdi+4]            ; data
    
    .print_lines:
        mov rdi, r15
        mov rsi, 1024
        call _strlen

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

        ret

; Returns the byte-length of a given string up-to 1024 bytes. If the string has
; multi-byte UTF-8 characters, each byte is counted individually.
; Arguments:
;   rdi - Pointer to the null-terminated string buffer
;   rsi - Maximum number of characters to examine
; Return:
;   rax - Byte-length of the string (excluding null terminator), or zero if str
;         is a null pointer, and rsi if the null character was not found in the
;         first rsi bytes.
_strlen:
    xor eax, eax            ; al = 0
    test rdi, rdi
    jz .done

    cld                     ; Ensure we are scanning FORWARD
    mov rcx, rsi

    repne scasb             ; Scan while [rdi] != al AND rcx != 0

    xor rdi, rdi
    setz dil                ; Save og ZF flag

    mov rax, rsi
    sub rax, rcx            ; rax = bytes_scanned
    
    test dil, dil
    jz .done                ; ZF=0 -> no null found, we hit limit -> rax == rsi
    dec rax                 ; ZF=1 -> found null -> exclude null from length

    .done:
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
        call _draw_panel

        mov rdi, panel_help
        call _draw_panel

        mov rdi, panel_main
        call _draw_panel

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
        call _render_buffer_colored

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

; Prints a single line from the game board buffer to the screen. To scale the
; visual output, each byte from the buffer is duplicated horizontally when
; rendered.
; Lines width are by their respective widths:
;   - Logical board: GAME_BOARD_WIDTH
;   - Terminal board: TERMINAL_BOARD_WIDTH
; Arguments:
;   rdi - Pointer to the start of the game_board buffer line
;   rsi - X as an integer
;   rdx - Y as an integer
; Return:
;   rax - Number of bytes processed
_print_board_line:
    push r15
    push r14
    push r13
    push r12
    push rbx
    
    mov r15, rsi
    mov r14, rdx
    mov rbx, GAME_BOARD_WIDTH   ; read count

    push rdi                    ; Save for later use

    mov r8, GAME_BOARD_WIDTH
    imul r9, r8, MAX_COLOR_ESC_SEQ_SIZE
    sub rsp, r9

    mov r13, rsp        ; dst pointer
    mov r12, rdi        ; src pointer

    .render_cell:
        cmp byte [r12], 0x20
        je .render_space

        ; Better than movsb for 8-bytes or smaller str. Doesn't matter if
        ; length != qword, overflow bytes will be overwritten below
        mov rax, qword [color_prefix_seq]
        mov qword [r13], rax
        add r13, color_prefix_seq_len

        movzx edi, byte [r12]
        mov rsi, r13
        call _itoa

        add r13, rax

        movzx eax, byte [color_after_code_seq]
        mov [r13], al
        add r13, color_after_code_seq_len

        mov word [r13], 0x2020
        add r13, 2

        mov eax, [color_suffix_seq]
        mov [r13], eax
        add r13, color_suffix_seq_len

        jmp .continue

        .render_space:
            mov word [r13], 0x2020
            add r13, 2

        .continue:
            inc r12
            dec rbx
            jnz .render_cell

    mov rdi, rsp        ; arg 1: buffer pointer
    mov rsi, r13
    sub rsi, rsp        ; arg 2: length = end_ptr - start_ptr
    mov rdx, r15        ; arg 3: X
    mov r10, r14        ; arg 3: Y
    call write_to_screen
    
    mov r8, GAME_BOARD_WIDTH
    imul r9, r8, MAX_COLOR_ESC_SEQ_SIZE
    add rsp, r9         ; Restore stack
    pop rdi

    mov rax, r12
    sub rax, rdi        ; We return this (bytes read: src_end - src_start)

    pop rbx
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
    call _write_int_left_aligned

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
    call _write_int_left_aligned

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
    call _write_int_left_aligned

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
        call _render_buffer_colored 

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


; =======  Game Over Rendering  ============================================= ;

; Renders the Game Over screen with the final game statistics.
; Arguments:
;   None
; Return:
;   None
render_game_over:
    ; Clean the main panel
    mov rdi, panel_main
    call _draw_panel

    mov rdi, panel_game_over
    call _draw_panel

    mov edi, [score]
    mov rsi, GAME_OVER_VALUE_LEN
    mov rdx, GAME_OVER_POS_X
    mov r10, GAME_OVER_POS_Y
    call _write_int_left_aligned

    mov edi, [lines]
    mov rsi, GAME_OVER_VALUE_LEN
    mov rdx, GAME_OVER_POS_X
    mov r10, GAME_OVER_POS_Y
    add r10, 1
    call _write_int_left_aligned

    movzx edi, byte [level]
    mov rsi, GAME_OVER_VALUE_LEN
    mov rdx, GAME_OVER_POS_X
    mov r10, GAME_OVER_POS_Y
    add r10, 2
    call _write_int_left_aligned

    ret


; =======  Utils  =========================================================== ;

; Writes the given str to the screen at (X,Y), where (1,1) is the top-left
; corner. We'll use the `\x1b[Y;XH` cursor control sequence to position it.
; Errors out when X and/or Y > 999 or < 1
; Arguments:
;   rdi - Pointer to the str buffer
;   rsi - Length of the str
;   rdx - X as an integer
;   r10 - Y as an integer
; Return:
;   rax - Number of bytes written
write_to_screen:
    push rbx
    mov rbx, r10

    ; Terminal dimensions don't realistically exceed (999, 999)
    cmp rdx, 999
    ja .error
    cmp rbx, 999
    ja .error

    cmp rdx, 1
    jb .error
    cmp rbx, 1
    jb .error

    ; === PROLOGUE ===
    ; Stack frame for the function
    push rbp
    mov rbp, rsp
    sub rsp, 10                 ; X (3B) + Y (3B) + `\x1b`, `[`, `;`, `H`

    ; Save originals for later
    push rsi
    push rdi 
    push rdx

    mov byte [rbp-10], `\x1b`
    mov byte [rbp-9], `[`

    mov rdi, rbx                ; Y coordinate
    lea rsi, [rbp-8]
    call _itoa

    mov rbx, rax                ; Y str len
    mov byte [rbp-8+rbx], `;`

    pop rdi                     ; X coordinate (rdx in stack)
    lea rsi, [rbp-7+rbx]        ; 8 accounts for the `;`
    call _itoa

    add rbx, rax                ; Y + X str len
    mov byte [rbp-7+rbx], `H`

    ; Print the ANSI escape string to position cursor
    mov rax, 1
    mov rdi, 1
    lea rsi, [rbp-10]
    lea rdx, [rbx+4]
    syscall

    cmp rax, rdx                ; null terminator is not written
    jne .error_post_prologue

    ; Print the actual string
    mov rax, 1
    mov rdi, 1
    pop rsi
    pop rdx
    syscall

    ; Restore stack
    mov rsp, rbp
    pop rbp

    pop rbx
    ret

    .error_post_prologue:
        mov rsp, rbp
        pop rbp
        pop rbx
        mov rax, 0
        ret

    .error:
        pop rbx
        mov rax, 0
        ret

; Converts an integer into its ASCII representation
; Arguments:
;   rdi - Integer
;   rsi - Pointer to the caller-allocated buffer
; Return:
;   rax - Length of the generated string
_itoa:
    mov rax, rdi
    mov r9, 10
    xor r10, r10          ; str ptr
    xor r11, r11          ; Pushed digits

    .get_digits:
        xor rdx, rdx
        div r9

        push rdx
        inc r11

        test rax, rax
        jnz .get_digits

    mov rax, r11         ; str len (ret value)

    .digit_to_ascii:
        pop r9         ; Retrieves digits in correct order
        dec r11

        lea rcx,  [r9 + '0']
        mov byte [rsi + r10], cl
        inc r10

        test r11, r11
        jnz .digit_to_ascii

    mov byte [rsi + r10], 0x0
    ret

; Renders an integer value to the screen with right alignment. If the rendered
; digit count is smaller than the specified maximum digit count, left padding
; is added so the value remains visually aligned.
; Arguments:
;   rdi - Integer value to render
;   rsi - Length of destination field. Must be greater or equal than the maximum
;         digit count for the rendered value (e.g. 3 for rdi = 120)
;   rdx - X coordinate
;   r10 - Y coordinate
;   r8 - Length 
; Return:
;   None
_write_int_left_aligned:
    push r15
    push r14
    push r13
    push r12

    mov r15, rsi
    mov r14, rdx
    mov r13, r10
    
    sub rsp, r15

    ; rdi already set
    mov rsi, rsp
    call _itoa

    mov r12, rax        ; Size of str

    mov r8, r15
    sub r8, r12         ; Alignment
    jz .print_value

    ; --- Alignment required ---
    sub rsp, r8         ; Reserve space BEFORE the str to place alignment
    mov r9, rsp

    mov rax, 0x20
    mov rdi, rsp
    mov rcx, r8
    cld                 ; Makes sure stosb runs forward
    rep stosb

    push r8

    mov rdi, r9         ; push advances rsp
    mov rsi, r8
    mov rdx, r14
    mov r10, r13
    call write_to_screen

    pop r8
    add rsp, r8

    .print_value:
        mov rdi, rsp
        mov rsi, r12
        mov rdx, r14
        add rdx, r8
        mov r10, r13
        call write_to_screen

    add rsp, r15

    pop r12
    pop r13
    pop r14
    pop r15
    ret

; Converts a buffer (line/piece part) into colored ANSI blocks and renders them
; to the screen. To scale the visual output, each cell is duplicated horizontally when
; rendered.
; Arguments:
;   rdi - Source buffer address
;   rsi - Buffer length (number of cells)
;   rdx - Screen X position
;   r10 - Screen Y position
; Returns:
;   rax - Number of cells processed
_render_buffer_colored:
    push rbp
    mov rbp, rsp

    push r15
    push r14
    push r13
    push r12
    push rbx

    push rdi                    ; Save for later use

    imul r8, rsi, MAX_COLOR_ESC_SEQ_SIZE
    sub rsp, r8

    mov r15, rdx
    mov r14, r10
    mov rbx, rsi

    mov r13, rsp        ; dst pointer
    mov r12, rdi        ; src pointer

    .render_cell:
        cmp byte [r12], 0x20
        je .render_space

        ; Better than movsb for 8-bytes or smaller str. Doesn't matter if
        ; length != qword, overflow bytes will be overwritten below
        mov rax, qword [color_prefix_seq]
        mov qword [r13], rax
        add r13, color_prefix_seq_len

        movzx edi, byte [r12]
        mov rsi, r13
        call _itoa

        add r13, rax

        movzx eax, byte [color_after_code_seq]
        mov [r13], al
        add r13, color_after_code_seq_len

        mov word [r13], 0x2020
        add r13, 2

        mov eax, [color_suffix_seq]
        mov [r13], eax
        add r13, color_suffix_seq_len

        jmp .continue

        .render_space:
            mov word [r13], 0x2020
            add r13, 2

        .continue:
            inc r12
            dec rbx
            jnz .render_cell

    mov rdi, rsp        ; arg 1: buffer pointer
    mov rsi, r13
    sub rsi, rsp        ; arg 2: length = end_ptr - start_ptr
    mov rdx, r15        ; arg 3: X
    mov r10, r14        ; arg 3: Y
    call write_to_screen
    
    ; Restore stack to the location it was after the 6 register push (6 * 8 = 48 bytes)
    lea rsp, [rbp - 48]

    pop rdi

    mov rax, r12
    sub rax, rdi        ; We return this (bytes read: src_end - src_start)

    pop rbx
    pop r12
    pop r13
    pop r14
    pop r15

    leave
    ret
