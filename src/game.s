global process_input, print_board, test_board
global GAME_BOARD_WIDTH
default rel

GAME_BOARD_WIDTH        equ 13
GAME_BOARD_HEIGHT       equ 20

section .rodata
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
    ;   - 0x20: empty cell (space)
    ;   - o, i, s, z, l, j, t: identifies part of a piece. Represented as:
    ;       oo  iiii   ss  zz     l  j      t 
    ;       oo        ss    zz  lll  jjj  ttt
    game_board              times 260 db 0x20       ; 13 cols x 20 lines
    game_board_len          equ $-game_board

    spawn_piece             db 0                    ; Wether to spawn (1) a new piece on the board

section .bss
    ; Tracks the active piece:
    ;   - Offset 0: Width (cols)
    ;   - Offset 1: Height (rows)
    ;   - Offset 2: X position
    ;   - Offset 3: Y position
    ;   - Offset 4: Piece character
    ;   - Offset 5: Array length
    ;   - Offset 6: Array data (1 for solid, 0 for empty). Size defined by Offset 4
    active_piece            resb 22     ; Up to 22 chars (piece_i)

; TODO: When adding a new piece, verify both width and height are at least one (or
; that they match one of the figures)

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


; =======  Piece Movement  ================================================== #

; Moves the active piece one position (right, left, or down). (0, 0) is not a
; valid move. This function orchestrates the whole flow:
;   1. Erase the piece from its current position
;   2. Call can_move(dx, dy)
;   3. If yes, update x_pos/y_pos
;   4. Move the piece at the (possible new) position
; Arguments:
;   rdi - Vertical displacement (dy): 1 for Down, 0 for horizontal moves
;   rsi - Horizontal displacement (dx): -1 for Left, 1 for Right, 0 for Down
; Return:
;   rax - Whether the piece was moved (1) or not (0)   
move_piece:
    push r15
    push r14
    push r13

    mov r15, rdi
    mov r14, rsi
    mov r13, 1                              ; Piece was moved

    call _erase_piece

    mov rdi, r15
    mov rsi, r14
    call _can_move_piece

    test rax, rax
    jnz .draw_piece

    ; Put piece in original position
    mov r15, 0
    mov r14, 0
    mov r13, 0                              ; Piece was NOT moved

    .draw_piece:
        ; Update coordinates
        add r14b, byte [active_piece + 2]   ; X
        add r15b, byte [active_piece + 3]   ; Y
        mov [active_piece + 2], r14b
        mov [active_piece + 3], r15b

        movzx edi, [active_piece + 4]       ; Piece's char
        call _modify_piece_on_board

    mov rax, r13
    pop r13
    pop r14
    pop r15
    ret

; Erases a piece from its current position. Allows us to verify if the piece
; can be moved to a (possible new) location without colliding with itself.
; Arguments:
;   None
; Return:
;   None 
_erase_piece:
    mov edi, 0x20
    call _modify_piece_on_board

; Iterates through the active piece's array and writes a specified character to
; the corresponding coords on the game board. This helper is used for both
; setting the piece and erasing it.
; Arguments:
;   rdi - The char to write to the board: 0x20 to erase, or the piece's specific
;         character.
; Returns:
;   None
_modify_piece_on_board:
    ; Using r32 as is 1-byte smaller in machine code and achieves the same
    movzx r8d, byte [active_piece]       ; Piece width
    movzx r9d, byte [active_piece + 1]   ; Piece height
    movzx r10d, byte [active_piece + 2]  ; Piece X pos

    ; Just a label plus a constant displacement, with no base/index registers,
    ; NASM will automatically compile this as a RIP-relative load.
    lea r11, [active_piece + 6]         ; src pointer

    movzx ecx, byte [active_piece + 3]
    imul eax, ecx, GAME_BOARD_WIDTH
    add rax, r10                        ; rax = (y * board_width) + x

    lea rcx, [game_board]               ; RIP-relative load
    add rax, rcx                        ; dst pointer = game_board[rax]

    .outer_loop_start:
        mov rcx, r8                     ; Reset width

        .inner_loop_start:
            cmp byte [r11], 0
            jz .next_col

            mov byte [rax], dil         ; Set that piece's cell

            .next_col:
                inc r11
                inc rax
                dec rcx
                jnz .inner_loop_start   ; If dec makes rcx = 0, ZF is set to 1

    .outer_loop_end:
        sub rax, r8                     ; Reset dst ptr X
        lea rax, [rax + GAME_BOARD_WIDTH]
        dec r9
        jnz .outer_loop_start
    
    .return:
        ret

; Check if the active piece can be moved by one position (right, left, or
; down). (0, 0) is not a valid move.
; This assumes the active piece have been erased from the board BEFORE it
; was called.
; Arguments:
;   rdi - Vertical displacement (dy): 1 for Down, 0 for horizontal moves
;   rsi - Horizontal displacement (dx): -1 for Left, 1 for Right, 0 for Down
; Return:
;   rax - Whether the piece can be moved (1) or not (0)   
_can_move_piece:
    cmp rdi, rsi                        ; Invalid move
    je .false
    cmp rdi, 0
    jl .false

    movzx r8d, byte [active_piece + 2]
    add r8, rsi                         ; target_x = x + dx
    movzx r9d, byte [active_piece + 3]
    add r9, rdi                         ; target_y = y + dy

    ; Check left, right, down (there's no up)
    cmp r8, GAME_BOARD_WIDTH
    ja .false                           ; Unsigned check, also evaluates < 0 (two's complement -> 0xFFF..)
    cmp r9, GAME_BOARD_HEIGHT
    ja .false
    
    movzx ecx, byte [active_piece]      ; Piece width
    movzx edx, byte [active_piece + 1]  ; Piece height

    ; Now check opposite coords (bottom-right corner)
    lea r10, [r8 + rcx]
    cmp r10, GAME_BOARD_WIDTH
    ja .false

    lea r10, [r9 + rdx]
    cmp r10, GAME_BOARD_HEIGHT
    ja .false

    lea r10, [active_piece + 6]         ; src pointer

    imul r11d, r9d, GAME_BOARD_WIDTH
    add r11, r8                         ; (target_y * board_width) + target_x
    lea rax, [game_board]
    add r11, rax                        ; dst pointer = game_board[r11]

    .outer_loop_start:
        mov rax, rcx                    ; Reset width

        .inner_loop_start:
            cmp byte [r10], 0
            jz .next_col

            cmp byte [r11], 0x20
            jne .false

            .next_col:
                inc r10
                inc r11
                dec rax
                jnz .inner_loop_start

    .outer_loop_end:
        sub r11, rcx                    ; Reset dst ptr X
        lea r11, [r11 + GAME_BOARD_WIDTH]
        dec rdx
        jnz .outer_loop_start

    .true:
        mov rax, 1
        jmp .return

    .false:
        mov rax, 0
    
    .return:
        ret

