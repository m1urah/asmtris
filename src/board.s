global process_input, process_board, spawn_piece, choose_next_piece
global game_board, active_piece, score, level, lines, frames_until_drop
global next_piece, needs_next_piece_redraw
global GAME_BOARD_WIDTH, GAME_BOARD_HEIGHT, NUMBER_OF_HIDDEN_ROWS
global MAX_SCORE_DIG_LEN, MAX_LEVEL_DIG_LEN, MAX_LINES_DIG_LEN
extern move_piece, rotate_figure
default rel

NUMBER_OF_HIDDEN_ROWS   equ 4
GAME_BOARD_WIDTH        equ 13
GAME_BOARD_HEIGHT       equ 24      ; 4 first lines = hidden (spawn) zone

MAX_SCORE               equ 999999
MAX_SCORE_DIG_LEN       equ 6       ; digits
MAX_LEVEL_DIG_LEN       equ 3       ; 255
MAX_LINES               equ 7777
MAX_LINES_DIG_LEN       equ 4

MOVE_PIECE_FREQ         equ 30      ; 1 every 30 FPS
PIECE_STRUCT_MAX_SIZE   equ 22      ; piece_i is current max

section .rodata
    ; === TETROMINOS ===
    ; Following the Super Rotation System (SRS), the I piece uses a 4x4
    ; bouding box, J, L, S, T, Z pieces 3x3, and the O piece 2x2.

    piece_i:
        db 4            ; Bounding box width
        db 4            ; Bounding box height
        db 4            ; Initial X
        db 0            ; Initial Y
        db 'i'          ; Piece character
        db 16           ; Size of array (array length)
        db 0, 0, 0, 0   ; Array data (1 for solid, 0 for empty)
        db 1, 1, 1, 1
        db 0, 0, 0, 0
        db 0, 0, 0, 0
        
    piece_s:
        db 3, 3, 5, 0, 's', 9
        db 0, 1, 1
        db 1, 1, 0
        db 0, 0, 0
        
    piece_z:
        db 3, 3, 5, 0, 'z', 9
        db 1, 1, 0
        db 0, 1, 1
        db 0, 0, 0
        
    piece_l:
        db 3, 3, 5, 0, 'l', 9
        db 0, 0, 1
        db 1, 1, 1
        db 0, 0, 0
        
    piece_j:
        db 3, 3, 5, 0, 'j', 9
        db 1, 0, 0
        db 1, 1, 1
        db 0, 0, 0
        
    piece_t:
        db 3, 3, 5, 0, 't', 9
        db 0, 1, 0
        db 1, 1, 1
        db 0, 0, 0

    piece_o:
        db 2, 2, 5, 0, 'o', 4
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
    ; Logical game board. Possible values:
    ;   - 0x20: empty cell (space)
    ;   - o, i, s, z, l, j, t: identifies part of a piece. Represented as:
    ;       oo  iiii   ss  zz     l  j      t 
    ;       oo        ss    zz  lll  jjj  ttt
    game_board              times 312 db 0x20       ; 13 cols x 24 lines
    game_board_len          equ $-game_board

    score                   dd 0
    lines                   dd 0
    level                   db 0
    
    frames_until_drop       db MOVE_PIECE_FREQ
    spawn_new_piece         db 1
    needs_next_piece_redraw db 1

    level_speeds:   ; Lvl 0, 1, 2 ... 29+
        db 48, 43, 38, 33, 28, 23, 18, 13, 8, 6
        db 5, 5, 5, 4, 4, 4, 3, 3, 3, 2, 2, 2
        db 2, 2, 2, 2, 2, 2, 2, 1

section .bss
    ; Tracks the active piece:
    ;   - Offset 0: Width (cols)
    ;   - Offset 1: Height (rows)
    ;   - Offset 2: X position (might be negative to account for empty cols)
    ;   - Offset 3: Y position
    ;   - Offset 4: Piece character
    ;   - Offset 5: Array length
    ;   - Offset 6: Array data (1 for solid, 0 for empty). Size defined by Offset 4
    active_piece            resb PIECE_STRUCT_MAX_SIZE
    next_piece              resb PIECE_STRUCT_MAX_SIZE

section .text

; =======  Entrypoint  ====================================================== ;

; Process all inputs from the user except for quit.
; Arguments:
;   rdi - Pointer to the input buffer
;   rsi - Length of the input
; Return:
;   None
process_input:
    test rsi, rsi
    jz .return

    ; (X, Y) are set on the top-left corner. Allow movement when piece is partially
    ; visible
    cmp byte [active_piece + 3], NUMBER_OF_HIDDEN_ROWS -1    ; Math done by NASM
    jl .return

    push r15
    xor r15, r15        ; Down move?

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
    cmp eax, `\e[C`
    je .do_right
    cmp eax, `\e[A`
    je .do_up
    cmp eax, `\e[B`
    je .do_down

    jmp .done

    .do_up:     ; rotate
        call rotate_figure
        jmp .done

    .do_left:   ; (0, -1)
        mov rdi, 0
        mov rsi, -1
        jmp .apply_move

    .do_right:  ; (0, 1)
        mov rdi, 0
        mov rsi, 1
        jmp .apply_move

    .do_down:   ; (1, 0)
        mov rdi, 1
        mov rsi, 0
        mov r15, 1

    .apply_move:
        call move_piece

        ; --- Score Update ---
        test rax, rax
        jz .done            ; Move failed, skip score

        test r15, r15
        jz .done            ; Not a down move, skip score

        mov rdi, 1
        call update_score

    .done:
        pop r15
    
    .return:
        ret

; Processes the current state of the board to clear lines and updates the
; score accordingly
; Arguments:
;   None
; Return:
;   None
process_board:
    cmp byte [frames_until_drop], 0
    jnz .return

    ; Reset timer
    mov byte [frames_until_drop], MOVE_PIECE_FREQ

    cmp byte [spawn_new_piece], 0
    jnz .spawn_routine

    call apply_gravity
    ret

    .spawn_routine:
        call spawn_piece
        call clear_full_rows
        mov rdi, rax
        call update_score   ; No-op if rdi = 0

        ; Flag that the view needs to update the next piece
        mov byte [needs_next_piece_redraw], 1

    .return:
        ret

; =======  Gravity  ========================================================= ;

; Attempts to move the active piece one position down. If the movement
; fails, the piece has either hit the bottom or a stack of blocks, which
; prompts a new piece to be spawned.
; Arguments:
;   None
; Return:
;   None
apply_gravity:
    mov rdi, 1
    xor rsi, rsi
    call move_piece     ; Move 1 down (1, 0)

    test rax, rax
    jnz .return         ; Piece moved, no need to spawn a new one

    mov byte [spawn_new_piece], 1

    .return:
        ret

; Spawns the next piece at its starting (X, Y) coordinates in the hidden zone,
; then generates a new next piece.
; Arguments:
;   None
; Return:
;   None
spawn_piece:
    lea rsi, [next_piece]           ; Src index
    lea rdi, [active_piece]         ; Dst index
    mov rcx, PIECE_STRUCT_MAX_SIZE  ; How many bytes to copy

    rep movsb

    call choose_next_piece
    mov byte [spawn_new_piece], 0

    .return:
        ret

; Randomly selects the next piece using the getrandom syscall. The piece is
; displayed on the screen and staged for used by spawn_piece.
;   None
; Return:
;   None
choose_next_piece:
    ; 1. Get random byte
    sub rsp, 1

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

    add rsp, 1

    lea r8, [piece_selector]    ; We cannot combine both instructions because of
    mov r9, [r8 + rax * 8]      ; RIP-relative addressing

    ; 3. Set new values in next_piece
    %assign i 0

    %rep 6
        movzx r8d, byte [r9 + i]
        mov byte [next_piece + i], r8b
        %assign i i + 1
    %endrep
    
    ; r8 = array length (min = 4)
    ; offset by 5 -> 5 + arr_length = final byte
    .set_array_data:
        movzx r10d, byte [r9 + 5 + r8]
        mov byte [next_piece + 5 + r8], r10b

        dec r8
        jnz .set_array_data

    .return:
        ret


; =======  Row Clearing  ==================================================== ;

; Checks every single non-hidden row on the board from bottom to top, clearing
; full lines.
; Arguments:
;   None
; Return
;   rax - Number cleared lines
clear_full_rows:
    push r15
    push r14

    mov r14, 0                      ; Cleared lines counter (for scoring)
    mov r15, GAME_BOARD_HEIGHT
    dec r15                         ; (Y) Last row (first is 0)

    .check_rows_loop:
        mov rdi, r15
        call _is_line_full

        test rax, rax
        jz .next_row

        mov rdi, r15
        call _shift_rows_down
        inc r14

        .next_row:
            dec r15
            cmp r15, NUMBER_OF_HIDDEN_ROWS
            jae .check_rows_loop

    mov rax, r14
    test rax, rax
    jz .return

    add [lines], r14w

    .return:
        pop r14
        pop r15
        ret

; Checks if given row is completed (no 0x20 bytes).
; Arguments:
;   rdi - Row to check
; Return:
;   rax - 1 (True) full, 0 (False) not full.
_is_line_full:
    mov rax, 0

    cmp rdi, NUMBER_OF_HIDDEN_ROWS
    jl .return                      ; Hidden rows DON'T shift

    ; r8 points to the first byte of the given row
    imul rdx, rdi, GAME_BOARD_WIDTH
    lea r8, [game_board]
    add r8, rdx

    mov rcx, GAME_BOARD_WIDTH

    .check_row_loop:
        cmp byte [r8], 0x20
        je .return
        inc r8
        dec rcx
        jnz .check_row_loop

    mov rax, 1
    .return:
        ret

; It takes the completed Y row and copies every non-hidden row above it down by
; exactly one row, removing the cleared row from the board. Top row is cleared
; with spaces.
; Arguments:
;   rdi - Row to be cleared
; Return:
;   None
_shift_rows_down:
    cmp rdi, NUMBER_OF_HIDDEN_ROWS
    jl .return                      ; Hidden rows DON'T shift

    imul rcx, rdi, GAME_BOARD_WIDTH
    mov rdx, NUMBER_OF_HIDDEN_ROWS
    imul rdx, rdx, GAME_BOARD_WIDTH

    ; r8 (src) points to the last byte of the row directly ABOVE the cleared line
    ; r9 (dst) points to the last byte of the cleared line
    lea r8, [game_board]
    add r8, rcx
    dec r8                          ; rcx is currently at first byte
    
    lea r9, [r8 + GAME_BOARD_WIDTH]

    .shift_loop:
        movzx r10d, byte [r8]
        mov byte [r9], r10b

        dec r8
        dec r9
        dec rcx
        cmp rcx, rdx
        jg .shift_loop

    ; r9 now points to the last BYTE of first NON-HIDDEN row
    mov rcx, GAME_BOARD_WIDTH
    .empty_top_row:
        mov byte [r9], 0x20
        dec r9
        dec rcx
        jnz .empty_top_row

    .return:
        ret


; =======  Scoring  ======================================================== ;

; Calculates and updates the game score based on the number of cleared lines.
; Uses the standard Nintendo-style point system: Base Points * (Level + 1).
; Where base points can be:
;   - 1 line : 40 points
;   - 2 lines: 100 points
;   - 3 lines: 300 points
;   - 4 lines: 1200 points 
; Arguments:
;   rdi - Number of cleared lines
; Return:
;   None
update_score_lines:
    test rdi, rdi
    jz .return

    cmp rdi, 1
    mov rax, 40
    je .calculate

    cmp rdi, 2
    mov rax, 100
    je .calculate

    cmp rdi, 3
    mov rax, 300
    je .calculate

    cmp rdi, 4
    mov rax, 1200
    jne .return                 ; More than 4 clear lines? Smth went wrong

    .calculate:
        movzx ecx, byte [level]
        inc rcx

        xor rdx, rdx
        mul rcx                 ; rax = base points * (level + 1)

    mov rdi, rax
    call update_score

    .return:
        ret

; Updates the score based on the input number.
; Arguments:
;   rdi - The amount of points to add to the score
; Return:
;   None
update_score:
    test rdi, rdi
    jz .return

    add dword [score], edi

    .return:
        ret
