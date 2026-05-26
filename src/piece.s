default rel
global move_piece, rotate_figure, calculate_hard_drop, do_hard_drop, init_piece
global lock_delay_active, lock_delay, lock_resets, spawn_piece, choose_next_piece
global active_piece, next_piece, LOCK_DELAY_VALUE, PIECE_STRUCT_MAX_SIZE
extern game_board, GAME_BOARD_WIDTH, GAME_BOARD_HEIGHT, NUMBER_OF_HIDDEN_ROWS       ; game.s

LOCK_DELAY_VALUE        equ 30  ; 0.5 sec at 60fps
MAX_LOCK_RESETS         equ 15  ; Prevent infinite stalling

PIECE_STRUCT_MAX_SIZE   equ 23      ; piece_i is current max

section .rodata
    ; To have adequate rotation, the I piece uses a 4x4 bounding box, J, L, S,
    ; T, Z pieces 3x3, and the O piece 2x2 (so that it can't be rotated).

    piece_i:
        db 4            ; Bounding box width
        db 4            ; Bounding box height
        db 4            ; Initial X
        db 0            ; Initial Y
        db 51           ; Xterm-256 color #00F5FF
        db 16           ; Size of array (array length)
        db 0, 0, 0, 0   ; Array data (1 for solid, 0 for empty)
        db 1, 1, 1, 1
        db 0, 0, 0, 0
        db 0, 0, 0, 0
        
    piece_s:
        db 3, 3, 5, 0, 46, 9            ; #39FF14
        db 0, 1, 1
        db 1, 1, 0
        db 0, 0, 0
        
    piece_z:
        db 3, 3, 5, 0, 203, 9           ; #FF3131
        db 1, 1, 0
        db 0, 1, 1
        db 0, 0, 0
        
    piece_l:
        db 3, 3, 5, 0, 208, 9           ; #FF7A00
        db 0, 0, 1
        db 1, 1, 1
        db 0, 0, 0
        
    piece_j:
        db 3, 3, 5, 0, 75, 9            ; #3A86FF
        db 1, 0, 0
        db 1, 1, 1
        db 0, 0, 0
        
    piece_t:
        db 3, 3, 5, 0, 165, 9           ; #4800ff
        db 0, 1, 0
        db 1, 1, 1
        db 0, 0, 0

    piece_o:
        db 2, 2, 5, 0, 226, 4           ; #FFF200
        db 1, 1
        db 1, 1

    piece_selector:
        dq piece_i
        dq piece_s
        dq piece_z
        dq piece_l
        dq piece_j
        dq piece_t
        dq piece_o

section .data
    lock_delay          db 0    ; Frames
    lock_delay_active   db 0    ; Active = 1
    lock_resets         db 0    ; Tracks how many times timer was reset

section .bss
    ; Tracks the active piece:
    ;   - Offset 0: Width (cols)
    ;   - Offset 1: Height (rows)
    ;   - Offset 2: X position (might be negative to account for empty cols)
    ;   - Offset 3: Y position
    ;   - Offset 4: Y position (hard drop)
    ;   - Offset 5: Piece color
    ;   - Offset 6: Array length
    ;   - Offset 7: Array data (1 for solid, 0 for empty). Size defined by Offset 6
    active_piece            resb PIECE_STRUCT_MAX_SIZE
    next_piece              resb PIECE_STRUCT_MAX_SIZE

section .text

; =======  Initialization  ================================================== ;

; Initializes piece-related memory structures by clearing the active and next
; piece buffers, and resetting the lock delay state.
; Arguments:
;   None
; Return:
;   None
init_piece:
    lea rdi, [active_piece]
    mov rcx, PIECE_STRUCT_MAX_SIZE
    rep stosb

    lea rdi, [next_piece]
    mov rcx, PIECE_STRUCT_MAX_SIZE
    rep stosb

    mov byte [lock_delay], 0
    mov byte [lock_delay_active], 0
    mov byte [lock_resets], 0
    
    ret


; =======  New Piece  ======================================================= ;

; Spawns the next piece at its starting (X, Y) coordinates in the hidden zone,
; then generates a new next piece.
; Arguments:
;   None
; Return:
;   None
spawn_piece:
    lea rsi, [next_piece]           ; src index
    lea rdi, [active_piece]         ; dst index
    mov rcx, PIECE_STRUCT_MAX_SIZE  ; How many bytes to copy

    rep movsb

    call choose_next_piece
    call calculate_hard_drop
    
    mov rax, 0

    .return:
        ret

; Randomly selects the next piece using the getrandom syscall. The piece is
; displayed on the screen and staged for used by spawn_piece.
;   None
; Return:
;   None
choose_next_piece:
    ; 1. Get random byte
    sub rsp, 8

    mov rax, 318        ; sys_getrandom
    mov rdi, rsp
    mov rsi, 1
    xor rdx, rdx
    syscall

    cmp rax, 1          ; error (used only for jne)
    jne .return

    ; 2. Get piece base on 0-6 index
    mov r8, 7

    movzx eax, byte [rsp]
    xor rdx, rdx
    div r8
    mov rax, rdx

    ; 3. Set new values in next_piece
    lea r8, [piece_selector]        ; RIP-relative addressing
    mov rsi, [r8 + rax * 8]         ; src index
    lea rdi, [next_piece]           ; dst index

    cld

    ; Copy first 4 bytes (pieces do not have same Offset 4)
    mov rcx, 4
    rep movsb

    mov byte [rdi], 0
    inc rdi

    ; Copy remaining bytes
    mov rcx, PIECE_STRUCT_MAX_SIZE - 4
    rep movsb

    .return:
        add rsp, 8
        ret


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

    call _erase_piece_from_board

    mov rdi, r15
    mov rsi, r14
    call _can_move_piece
    mov r13, rax            ; Save success (1) or failure (0)

    test r13, r13
    jz .draw_piece

    add byte [active_piece + 2], r15b   ; X
    add byte [active_piece + 3], r14b   ; Y

    .draw_piece:
        movzx edi, byte [active_piece + 5]
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
; down), (0, 0) is not valid. This function assumes the active piece has
; been erased from the board.
; Arguments:
;   rdi - Horizontal displacement (dx): -1 for Left, 1 for Right, 0 for Down
;   rsi - Vertical displacement (dy):    1 for Down, 0 for horizontal moves
; Return:
;   rax - Whether the piece can be moved (1) or not (0)   
_can_move_piece:
    mov rax, 0                          ; NOT moved

    cmp rdi, rsi                        ; Invalid move
    je .return
    cmp rsi, 0
    jl .return

    push r15
    push r14
    mov r15, rdi
    mov r14, rsi

    ; Apply movement offsets. sx needed, coordinates might be negative!!!
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

; Erases a piece from its current position. Allows us to verify if the piece
; can be moved to a (possible new) location without colliding with itself.
; Arguments:
;   None
; Return:
;   None 
_erase_piece_from_board:
    mov edi, 0x20
    call _modify_piece_on_board

; Iterates through the active piece's array and writes a specified value to the
; corresponding coords on the game board. This helper is used for both setting
; the piece and erasing it.
; Arguments:
;   rdi - The char to write to the board: 0x20 to erase, or the piece's specific
;         color.
; Returns:
;   None
_modify_piece_on_board:
    ; Using r32 as is 1-byte smaller in machine code and achieves the same
    movzx r8d, byte [active_piece]      ; Piece width
    movzx r9d, byte [active_piece + 1]  ; Piece height
    movsx r10, byte [active_piece + 2]  ; Piece X pos

    ; Just a label plus a constant displacement, with no base/index registers,
    ; NASM will automatically compile this as a RIP-relative load.
    lea r11, [active_piece + 7]         ; src pointer

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


; =======  Hard Drop  ======================================================= #

; Calculates the lowest possible valid Y position for the active piece.
; Arguments:
;   None
; Return:
;   None
calculate_hard_drop:
    push r15
    push r14

    movzx r15d, byte [active_piece + 3] ; Y
    mov r14, r15                        ; Save original

    call _erase_piece_from_board

    .calculate_final_y:
        mov byte [active_piece + 3], r15b
        inc r15

        mov rdi, 0
        mov rsi, 1
        call _can_move_piece

        test rax, rax
        jnz .calculate_final_y

    dec r15
    mov byte [active_piece + 4], r15b
    mov byte [active_piece + 3], r14b   ; Restore original
    
    ; Draw piece back to its original pos
    movzx edi, byte [active_piece + 5]
    call _modify_piece_on_board

    pop r14
    pop r15
    ret

; The active piece teleports to the lowest possible valid Y position, stored at
; its 4 offset.
; Arguments:
;   None
; Return:
;   rax - Number of skipped cells
do_hard_drop:
    movzx eax, byte [active_piece + 4]
    sub al, [active_piece + 3]  ; Skipped cells

    test rax, rax
    jz .return

    push r15
    mov r15, rax
    
    ; --- Cells skipped ---

    call _erase_piece_from_board

    ; Move from calculated hard-drop Y to current Y
    mov cl, byte [active_piece + 4]
    mov byte [active_piece + 3], cl

    movzx edi, byte [active_piece + 5]
    call _modify_piece_on_board

    mov rax, r15
    pop r15

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
    mov rax, qword [active_piece+7]
    mov rcx, qword [active_piece+15]
    push rcx
    push rax

    lea rdi, [active_piece+7]
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
    mov qword [active_piece+7], rax
    mov qword [active_piece+15], rcx

    .draw_piece:
        movzx edi, byte [active_piece + 5]  ; Piece's color
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

    lea r8, [active_piece + 7]          ; src pointer

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
