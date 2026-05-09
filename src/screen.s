global init_screen, update_screen
extern GAME_BOARD_WIDTH, NUMBER_OF_HIDDEN_ROWS
extern MAX_SCORE_DIG_LEN, MAX_LEVEL_DIG_LEN, MAX_LINES_DIG_LEN
extern game_board, score, level, lines, next_piece, needs_next_piece_redraw
default rel

TERMINAL_BOARD_WIDTH    equ 26
TERMINAL_BOARD_HEIGHT   equ 20
TERMINAL_BOARD_INIT_X   equ 26
TERMINAL_BOARD_INIT_Y   equ 2

STATS_STAT_START_X      equ 14  ; Max 6 chars per stat
STATS_STAT_START_Y      equ 2
STATS_VALUE_LEN         equ 6

NEXT_PIECE_START_Y      equ 3
NEXT_PIECE_START_Y_I    equ 2   ; I is 4 rows long, would overflow
NEXT_PIECE_START_X      equ 63
NEXT_PIECE_START_X_I    equ 62
NEXT_PIECE_START_X_O    equ 64

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
        db 21   ; width
        db 5    ; height
        db 1    ; col (X)
        db 1    ; line (Y)
        ; utf-8 chars are multi-byte, null terminator marks end of row
        db "┏━━━━━━━Stats━━━━━━━┓", 0
        db "┃ Score           X ┃", 0
        db "┃ Level           X ┃", 0
        db "┃ Lines           X ┃", 0
        db "┗━━━━━━━━━━━━━━━━━━━┛", 0

    panel_next:
        db 20, 6, 56, 1
        db "┏━━━━━━━Next━━━━━━━┓", 0
        db "┃                  ┃", 0
        db "┃                  ┃", 0
        db "┃                  ┃", 0
        db "┃                  ┃", 0
        db "┗━━━━━━━━━━━━━━━━━━┛", 0

    panel_help:
        db 21, 8, 56, 9
        db "┏━━━━━━━Help━━━━━━━┓", 0
        db "┃ Left      h, ←   ┃", 0
        db "┃ Right     l, →   ┃", 0
        db "┃ Down      j, ↓   ┃", 0
        db "┃ Rotate    k, ↑   ┃", 0
        db "┃ Drop      space  ┃", 0
        db "┃ Quit      q      ┃", 0
        db "┗━━━━━━━━━━━━━━━━━━┛", 0

    panel_main:
        db 30, 22, 24, 1
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
    call _print_board
    call _set_score
    call _set_level
    call _set_lines

    cmp byte [needs_next_piece_redraw], 1
    jne .return

    ; If dirty, redraw and clean the flag
    call _set_next_piece
    mov byte [needs_next_piece_redraw], 0

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
        mov rsi, r15
        mov rdx, r14
        call _print_board_line

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
;   rdx - X as an integer
;   r10 - Y as an integer
_print_board_line:
    push r15
    mov r15, TERMINAL_BOARD_WIDTH   ; buffer size
    mov rcx, GAME_BOARD_WIDTH       ; count (width)

    sub rsp, r15

    mov r10, rsp                    ; dst pointer
    mov r11, rdi                    ; src pointer

    .dup_byte:
        mov al, [r11]
        mov ah, al                  ; dup byte        
        mov [r10], ax

        inc r11
        add r10, 2
        dec rcx
        jnz .dup_byte


    mov rbx, r11
    sub rbx, rdi                ; We return this (bytes read: src_end - src_start)

    mov rdi, rsp
    mov rax, r10
    mov r10, rdx
    mov rdx, rsi

    mov rsi, rax
    sub rsi, rsp                ; length = dst_end - dst_start
    call write_to_screen
    
    add rsp, r15                ; Restore stack
    pop r15

    mov rax, rbx
    ret

; Renders the current game score to its designated place on the screen.
; Arguments:
;   None
; Return:
;   None
_set_score:
    mov edi, dword [score]

    mov rsi, MAX_SCORE_DIG_LEN
    mov rdx, STATS_STAT_START_Y
    call _set_stat
    ret

; Renders the current level to its designated place on the screen.
; Arguments:
;   None
; Return:
;   None
_set_level:
    movzx edi, byte [level]

    mov rsi, MAX_LEVEL_DIG_LEN
    mov rdx, STATS_STAT_START_Y
    add rdx, 1
    call _set_stat
    ret

; Renders the number of cleared lines to its designated place on the screen.
; Arguments:
;   None
; Return:
;   None
_set_lines:
    mov edi, dword [lines]

    mov rsi, MAX_LINES_DIG_LEN
    mov rdx, STATS_STAT_START_Y
    add rdx, 2
    call _set_stat
    ret

; Renders the given stat value to the screen.
; Arguments:
;   rdi - Stat value (score, level, or lines)
;   rsi - Max digit count (see board.s MAX_*_DIG_LEN)
;   rdx - Start row
; Return:
;   None
_set_stat:
    push r15
    push r14
    push r13
    push r12

    mov r15, rsi
    mov r14, rdx

    sub rsp, r15

    ; rdi already set
    mov rsi, rsp
    call _itoa              ; Convert score to str

    mov r13, rax            ; str len
    mov r12, STATS_VALUE_LEN
    sub r12, r13            ; alignment
    jz .print_score

    sub rsp, r12

    ; Align score right by adding spaces
    mov rax, 0x20
    mov rdi, rsp
    mov rcx, r12
    rep stosb
    
    mov rdi, rsp
    mov rsi, r12
    mov rdx, STATS_STAT_START_X
    mov r10, r14
    call write_to_screen

    add rsp, r12

    .print_score:
        mov rdi, rsp
        mov rsi, r13
        mov rdx, STATS_STAT_START_X
        add rdx, r12
        mov r10, r14
        call write_to_screen
    
    add rsp, r15
    pop r12
    pop r13
    pop r14
    pop r15
    ret

; Renders the next piece to the screen.
; Arguments:
;   None
; Return:
;   None
_set_next_piece:
    call _clear_next_piece_panel

    push rbx

    movzx ebx, byte [next_piece + 1]    ; Height
    test rbx, rbx                       ; Height != 0
    jz .return

    cmp bl, byte [next_piece]           ; Height == Width
    jne .return

    push r15
    push r14
    push r13
    push r12
    push rbp

    mov r12, rbx                        ; Height counter
    lea r13, [next_piece + 6]           ; Array pointer

    sub rsp, rbx
    sub rsp, rbx

    cmp rbx, 4
    mov r15, NEXT_PIECE_START_X_I
    mov r14, NEXT_PIECE_START_Y_I
    je .outer_loop_start

    mov r14, NEXT_PIECE_START_Y

    cmp rbx, 2
    mov r15, NEXT_PIECE_START_X_O
    je .outer_loop_start

    mov r15, NEXT_PIECE_START_X

    .outer_loop_start:
        mov rcx, rbx
        mov rbp, rsp

        .inner_loop_start:
            ; mov rdx, r12
            movzx rdx, byte [next_piece + 4]
            cmp byte [r13], 1

            mov rsi, 0x20
            cmovne rdx, rsi             ; Byte not set -> not piece part

            mov byte [rbp], dl
            mov byte [rbp+1], dl

            add rbp, 2
            inc r13
            dec rcx
            jnz .inner_loop_start

    .outer_loop_end:
        mov rdi, rsp
        mov rsi, rbx
        add rsi, rbx
        mov rdx, r15
        mov r10, r14
        call write_to_screen

        inc r14
        dec r12
        jnz .outer_loop_start
    
    add rsp, rbx
    add rsp, rbx
    
    pop rbp
    pop r12
    pop r13
    pop r14
    pop r15
    
    .return:
        pop rbx
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
