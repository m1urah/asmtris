global move_piece, rotate_figure
global lock_delay_active, lock_delay, lock_resets
global LOCK_DELAY_VALUE
extern game_board, active_piece
extern GAME_BOARD_WIDTH, GAME_BOARD_HEIGHT
default rel

LOCK_DELAY_VALUE        equ 30  ; 0.5 sec at 60fps
MAX_LOCK_RESETS         equ 15  ; Prevent infinite stalling

section .data
    lock_delay          db 0    ; Frames
    lock_delay_active   db 0    ; Active = 1
    lock_resets         db 0    ; Tracks how many times timer was reset

section .text

; =======  Piece Movement  ================================================== #

; Moves the active piece one position (right, left, or down). (0, 0) is not a
; valid move.
; If the piece cannot move down, the "lock delay" timer starts, which refers to
; how many frames a piece waits while on the ground before locking.
; Arguments:
;   rdi - Horizontal displacement (dx): -1 for Left, 1 for Right, 0 for Down
;   rsi - Vertical displacement (dy):    1 for Down, 0 for horizontal moves
; Return:
;   rax - Whether the piece was moved (1) or not (0)
move_piece:
    push r15
    push r14
    push r13
    mov r13, 0              ; Piece was not moved

    cmp rdi, rsi
    je .return

    mov r15, rdi
    mov r14, rsi
    mov r13, 1              ; Assume piece will move

    call can_move_piece
    mov r13, rax            ; Save success (1) or failure (0)

    test r13, r13
    jz .draw_piece

    ; If success, apply movement offsets. sx needed, coordinates might be negative!!!
    add byte [active_piece + 2], r15b   ; X
    add byte [active_piece + 3], r14b   ; Y

    .draw_piece:
        movzx edi, byte [active_piece + 4]
        call _modify_piece_on_board

    test r13, r13
    jz .piece_not_moved

    .piece_moved:
        cmp byte [lock_delay_active], 1
        jne .return

        cmp r14, 1      ; Down move?
        jne .horizontal_reset

        ; Disable timer and reset stall counter on successful down move
        mov byte [lock_delay_active], 0
        mov byte [lock_resets], 0
        jmp .return

    .horizontal_reset:
        cmp byte [lock_resets], MAX_LOCK_RESETS
        jge .return     ; Skip reset if limit reached

        inc byte [lock_resets]
        mov byte [lock_delay], LOCK_DELAY_VALUE
        jmp .return

    .piece_not_moved:
        cmp r14, 1
        jne .return

        ; If the piece couldn't move down, start timer
        cmp byte [lock_delay_active], 1
        je .return

        mov byte [lock_delay], LOCK_DELAY_VALUE
        mov byte [lock_delay_active], 1

    .return:
        mov rax, r13
        pop r13
        pop r14
        pop r15

        ret

; Check if the active piece can be moved by one position (right, left, or
; down), (0, 0) is not valid. The active piece is erased from the board before
; checking for possible movement.
; Arguments:
;   rdi - Horizontal displacement (dx): -1 for Left, 1 for Right, 0 for Down
;   rsi - Vertical displacement (dy):    1 for Down, 0 for horizontal moves
; Return:
;   rax - Whether the piece can be moved (1) or not (0)   
can_move_piece:
    mov rax, 0                          ; NOT moved

    cmp rdi, rsi                        ; Invalid move
    je .return
    cmp rsi, 0
    jl .return

    push r15
    push r14
    mov r15, rdi
    mov r14, rsi

    call _erase_piece_from_board

    movsx r8, byte [active_piece + 2]
    add r15, r8                         ; target_x = dx + x
    movsx r9, byte [active_piece + 3]
    add r14, r9                         ; target_y = dy + y

    mov rdi, r15
    mov rsi, r14
    call _can_place_piece

    pop r14
    pop r15

    .return:
        ret

; Draws a piece at its (X, Y) coordinates in the board.
; Arguments:
;   None
; Return:
;    None
_draw_piece:
    ; Update coordinates
    ; sx needed, coordinates might be negative!!!
    movsx r8, byte [active_piece + 2]   
    add r14, r8                         ; X
    movsx r8, byte [active_piece + 3]
    add r15, r8                         ; Y
    mov [active_piece + 2], r14b
    mov [active_piece + 3], r15b

    movzx edi, byte [active_piece + 4]  ; Piece's char
    call _modify_piece_on_board

; Erases a piece from its current position. Allows us to verify if the piece
; can be moved to a (possible new) location without colliding with itself.
; Arguments:
;   None
; Return:
;   None 
_erase_piece_from_board:
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
    movzx r8d, byte [active_piece]      ; Piece width
    movzx r9d, byte [active_piece + 1]  ; Piece height
    movsx r10, byte [active_piece + 2]  ; Piece X pos

    ; Just a label plus a constant displacement, with no base/index registers,
    ; NASM will automatically compile this as a RIP-relative load.
    lea r11, [active_piece + 6]         ; src pointer

    movsx rcx, byte [active_piece + 3]
    imul rax, rcx, GAME_BOARD_WIDTH
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


; =======  Piece Rotation  ================================================== #

; Rotates the current active figure 90 degrees clockwise. To verify this:
;   1. Erase the piece from its current position
;   2. Rotate piece
;   3. Check if the rotated piece can be placed at the current (X, Y) coords
;   4. If not, revert rotation
;   5. Draw piece
; Arguments:
;   None
; Return:
;   rax - Whether the piece was rotated (1) or not (0)   
rotate_figure:
    push r15

    call _erase_piece_from_board

    ; Backup the original figure array
    mov rax, qword [active_piece+6]
    mov rcx, qword [active_piece+14]
    push rcx
    push rax

    lea rdi, [active_piece+6]
    movzx esi, byte [active_piece]
    call _rotate_array

    movsx rdi, byte [active_piece+2]
    movsx rsi, byte [active_piece+3]
    call _can_place_piece

    test rax, rax
    mov r15, rax

    pop rax
    pop rcx
    jnz .draw_piece

    ; Restore original figure array
    mov qword [active_piece+6], rax
    mov qword [active_piece+14], rcx

    .draw_piece:
        movzx edi, byte [active_piece + 4]  ; Piece's char
        call _modify_piece_on_board

    mov rax, r15
    pop r15

    ret

; Rotates a square matrix 90 degrees clockwise. The process is as follows:
;   1. Transpose matrix by swapping the elements at index (i,j) with the
;      elements at (j,i): rows --> columns
;   2. Reverse the order of elements in every row.
; Arguments:
;   rdi - Pointer to the array containing the matrix
;   rsi - Number of cols/rows
; Return:
;   None
_rotate_array:
    lea rax, [rsi - 1]
    xor r8, r8              ; i (row)
    xor r9, r9              ; j (col)

    ; 1. Transpose
    .outer_loop_start_t:
        mov r9, r8          ; j (col) = i + 1
        inc r9              ; (i, j) where i = j never changes, skip it

        ; Calculate offsets
        mov r10, r8
        imul r10, rsi
        add r10, r9         ; (i, j) = (i x height) + j

        mov r11, r9
        imul r11, rsi
        add r11, r8         ; (j, i) = (j x width) + i

        .inner_loop_t:
            movzx ecx, byte [rdi + r10]
            movzx edx, byte [rdi + r11]

            mov byte [rdi + r10], dl
            mov byte [rdi + r11], cl

            inc r9
            inc r10
            add r11, rsi
            cmp r9, rsi
            jb .inner_loop_t

        inc r8
        cmp r8, rax
        jb .outer_loop_start_t 

    ; 2. Reverse rows
    xor r10, r10            ; current row
    mov r11, rsi
    imul r11, r11           ; max row offset
    .outer_loop_start_r:
        lea r8, [rdi + r10] ; ptr row start
        lea r9, [r8 + rax]  ; ptr row end

        .inner_loop_r:
            movzx ecx, byte [r8]
            movzx edx, byte [r9]

            mov byte [r8], dl
            mov byte [r9], cl

            inc r8
            dec r9
            cmp r8, r9
            jb .inner_loop_r

        add r10, rsi
        cmp r10, r11
        jb .outer_loop_start_r

    ret

; =======  Helpers  ========================================================= #

; Checks if the active piece can be placed at the specified (X, Y) coordinates
; without hitting the walls or other blocks.
; Arguments:
;   rdi - Target X coordinate (column)
;   rsi - Target Y coordinate (row)
; Return:
;   rax - 1 (True) if it can be placed, 0 (False) if not.
_can_place_piece:
    movzx ecx, byte [active_piece]      ; Piece width
    movzx edx, byte [active_piece + 1]  ; Piece height

    lea r8, [active_piece + 6]          ; src pointer

    imul r9d, esi, GAME_BOARD_WIDTH
    add r9, rdi                         ; (target_y * board_width) + target_x
    lea r10, [game_board]
    add r9, r10                         ; dst pointer = game_board[r11]

    mov r10, rdi                        ; x
    mov r11, rsi                        ; y

    .outer_loop_start:
        mov rax, rcx                    ; Reset width
        mov r10, rdi

        .inner_loop_start:
            cmp byte [r8], 0
            jz .next_col

            cmp r10, GAME_BOARD_WIDTH
            jae .false                   ; Unsigned check, also evaluates < 0 (two's complement -> 0xFFF..)
            cmp r11, GAME_BOARD_HEIGHT
            jae .false

            cmp byte [r9], 0x20
            jne .false

            .next_col:
                inc r8
                inc r9
                inc r10
                cmp r10, rax

                dec rax
                jnz .inner_loop_start

    .outer_loop_end:
        sub r9, rcx                    ; Reset dst ptr X
        lea r9, [r9 + GAME_BOARD_WIDTH]
        inc r11
        dec rdx
        jnz .outer_loop_start

    .true:
        mov rax, 1
        jmp .return

    .false:
        mov rax, 0
    
    .return:
        ret
