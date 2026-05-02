global process_input, print_board, test_board
extern write_to_screen
default rel

section .rodata
    ; === BOARD ===
    game_board_dim:
        db 13           ; Board Width
        db 21           ; Board height

    terminal_board_dim:
        db 26           ; Board Width
        db 20           ; Board height
        db 26           ; Initial X
        db 2            ; Initial Y

    ; === TETROMINOS ===
    ; Following the Super Rotation System (SRS), the I piece uses a 4x4
    ; bouding box, J, L, S, T, Z pieces 3x3, and the O piece 2x2.

    piece_i:
        db 4            ; Bounding box width
        db 4            ; Bounding box height
        db 4            ; Initial X
        db 0            ; Initial Y
        db 16           ; Size of array (array length)
        db 'i'          ; Piece character
        db 0, 0, 0, 0   ; Array data (1 for solid, 0 for empty)
        db 1, 1, 1, 1
        db 0, 0, 0, 0
        db 0, 0, 0, 0
        
    piece_s:
        db 3, 3, 5, 0, 9, 's'
        db 0, 1, 1
        db 1, 1, 0
        db 0, 0, 0
        
    piece_z:
        db 3, 3, 5, 0, 9, 'z'
        db 1, 1, 0
        db 0, 1, 1
        db 0, 0, 0
        
    piece_l:
        db 3, 3, 5, 0, 9, 'l'
        db 0, 0, 1
        db 1, 1, 1
        db 0, 0, 0
        
    piece_j:
        db 3, 3, 5, 0, 9, 'j'
        db 1, 0, 0
        db 1, 1, 1
        db 0, 0, 0
        
    piece_t:
        db 3, 3, 5, 0, 9, 't'
        db 0, 1, 0
        db 1, 1, 1
        db 0, 0, 0

    piece_o:
        db 2, 2, 5, 0, 4, 'o'
        db 1, 1
        db 1, 1

section .data
    ; Logical game board. Possible values:
    ; - 0x20: empty cell (space)
    ; - o, i, s, z, l, j, t: identifies part of a piece. Represented as:
    ;     oo  iiii   ss  zz     l  j      t 
    ;     oo        ss    zz  lll  jjj  ttt
    game_board              times 273 db 0x20       ; 13 cols x 21 lines
    game_board_len          equ $-game_board


section .text

; Process all inputs from the user except for quit.
; Arguments:
;   rdi - Pointer to the input buffer
;   rsi - Length of the input
; Return:
;   None
process_input:
    test rsi, rsi
    jz .done

    mov eax, [rdi]      ; Load 4 bytes (even if buffer is smaller)

    ; --- 1-Byte Commands (WASD) ---
    cmp al, 'a'
    je .do_left
    cmp al, 'd'
    je .do_right
    cmp al, 'w'
    je .do_up
    cmp al, 's'
    je .do_down

    ; --- 3-Byte Commands (Arrows) ---
    ; Mask EAX to 24 bits (0x00FFFFFF) to ignore the 4th LE byte
    and eax, 0x00FFFFFF

    cmp eax, `\e[D`
    je .do_left
    cmp eax, `^[[C`
    je .do_right
    cmp eax, `^[[A`
    je .do_up
    cmp eax, `^[[B`
    je .do_down

    .do_left:
    .do_right:
    .do_up:
    .do_down:
    .done:
        ret

test_board:
    %assign i 0
    %assign char 'a'

    %rep 20
        mov byte [game_board + i], char
        %assign i i + 13
        %assign char char + 1
    %endrep

    ret

; Updates the screen with the logical board. Each byte in game_board represents
; two in the screen_board.
; Arguments:
;   None
; Return:
;   None
print_board:
    movzx r15, byte [terminal_board_dim + 2]    ; Initial X
    movzx r14, byte [terminal_board_dim + 3]    ; Initial Y
    
    mov r13, r14
    add r13b, byte [terminal_board_dim + 1]     ; End Y = Y + height

    lea r12, [game_board]                       ; src ptr

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
        ret


; =======  Helpers  ======================================================== #

; Prints a line from the logical board into the screen. Lines width are
; by their respective widths:
;   - Logical board: [game_board_dim]
;   - Terminal board: [terminal_board_dim ]
; Arguments:
;   rdi - Pointer to the logical board
;   rsi - X coordinate
;   rdx - Y coordinate
; Return:
;   rax - Number of bytes written
_print_board_line:
    push r15
    movzx r15, byte [terminal_board_dim]     ; buffer size
    movzx rcx, byte [game_board_dim]        ; count (width)

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
