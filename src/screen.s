global init_board, update_screen
extern GAME_BOARD_WIDTH, NUMBER_OF_HIDDEN_ROWS
extern MAX_SCORE_DIG_LEN, MAX_LEVEL_DIG_LEN, MAX_LINES_DIG_LEN
extern game_board, score, level, lines
default rel

TERMINAL_BOARD_WIDTH    equ 26
TERMINAL_BOARD_HEIGHT   equ 20
TERMINAL_BOARD_INIT_X   equ 26
TERMINAL_BOARD_INIT_Y   equ 2

STATS_STAT_START_X      equ 14  ; Max 6 chars per stat
STATS_STAT_START_Y      equ 2
STATS_VALUE_LEN         equ 6

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
        db 1    ; line (Y)
        ; utf-8 chars are multi-byte, null terminator marks end of row
        db "┏━━━━━━━Stats━━━━━━━┓", 0
        db "┃ Score           X ┃", 0
        db "┃ Level           X ┃", 0
        db "┃ Lines           X ┃", 0
        db "┗━━━━━━━━━━━━━━━━━━━┛", 0

    panel_next:
        db 5, 56, 1
        db "┏━━━━━━━Next━━━━━━━┓", 0
        db "┃                  ┃", 0
        db "┃     ████████     ┃", 0
        db "┃                  ┃", 0
        db "┗━━━━━━━━━━━━━━━━━━┛", 0

    panel_help:
        db 8, 56, 8
        db "┏━━━━━━━Help━━━━━━━┓", 0
        db "┃ Left      h, ←   ┃", 0
        db "┃ Right     l, →   ┃", 0
        db "┃ Down      j, ↓   ┃", 0
        db "┃ Rotate    k, ↑   ┃", 0
        db "┃ Drop      space  ┃", 0
        db "┃ Quit      q      ┃", 0
        db "┗━━━━━━━━━━━━━━━━━━┛", 0

    panel_main:
        db 22, 24, 1
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
init_board:
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

    mov r12b, byte [rdi]        ; height
    mov r13b, byte [rdi+1]      ; col (X)
    mov r14b, byte [rdi+2]      ; line (Y)
    add r12b, r14b              ; end_Y = height + starting line (Y)
    lea r15, [rdi+3]            ; data
    
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
        test rcx, rcx
        jz .done

        mov al, [r11]
        mov ah, al                  ; dup byte        
        mov [r10], ax

        inc r11
        add r10, 2
        dec rcx
        jmp .dup_byte

    .done:
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
    lea r8, [score]
    mov edi, dword [r8]

    mov rsi, MAX_SCORE_DIG_LEN
    mov rdx, STATS_STAT_START_Y
    call _set_stat
    ret

_set_level:
    lea r8, [level]
    mov edi, dword [r8]

    mov rsi, MAX_LEVEL_DIG_LEN
    mov rdx, STATS_STAT_START_Y
    add rdx, 1
    call _set_stat
    ret

_set_lines:
    lea r8, [lines]
    mov edi, dword [r8]

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

_set_next_piece:
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
    jne .error

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
