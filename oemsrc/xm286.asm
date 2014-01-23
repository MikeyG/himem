;*******************************************************************************
;
; MoveExtended286
;	XMM Move Extended Memory Block for the 80286
;	Use Int 15h, Block Move
;
; Entry:
;	ES:BX	Points to a MoveExtendedStruc
;
; Return:
;	AX = 1	Success
;	AX = 0	Failure
;		Error Code in BL
;
; Registers Destroyed:
;	Flags
;
;			WARNING
;			=======
;
; This routine enables interrupts and can be re-entered
;
; Notes:
;	The case of copying from conventional to conventional memory
;	is not treated specially in this example.
;
; History:
;	Wed Jul 13 - AWG - Original version
;-------------------------------------------------------------------------------
ifndef	XM286INCLUDED
public	MoveExtMemory
endif
MoveExtMemory proc    near

	sti					; Be nice
	push	bp				; Set up stack frame so we
	mov	bp, sp				; can have local variables
	sub	sp, 18+(6*8)			; Space for local variables
Count	  = -4					; Local DWORD for byte count
MEReturn  = -6					; Local WORD for return code
SrcHandle = -8
DstHandle = -10
SrcLinear = -14
DstLinear = -18
GDT	  = -18-(6*8)				; Space for 6 GDT entries
	pusha
	push	ds
	push	es

	xor	ax, ax
	mov	[bp.MEReturn], ax			; Assume success
	mov	[bp.SrcHandle], ax
	mov	[bp.DstHandle], ax
	mov	ax, word ptr es:[si.bCount]	; Pick up length specified
	mov	word ptr [bp.Count], ax
	mov	cx, word ptr es:[si.bCount+2]
	mov	word ptr [bp.Count+2], cx
	or	cx, ax
	jcxz	short MEM2_Exit 		; Exit immediately if zero

	lea	bx, [si.SourceHandle]		; Normalize Source
	call	GetLinear286			; Linear address in DX:AX
	jc	short MEM2_SrcError		; Have Dest Error Code
	mov	word ptr [bp.SrcLinear], ax	; Save Linear address
	mov	word ptr [bp.SrcLinear+2], dx
	mov	[bp.SrcHandle], bx		; Save Handle for Unlock

	lea	bx, [si.DestHandle]		; Normalize Destination
	call	GetLinear286
	jc	short MEM2_Error
	mov	word ptr [bp.DstLinear], ax	; Save Linear address
	mov	word ptr [bp.DstLinear+2], dx
	mov	[bp.DstHandle], bx		; Save Handle for Unlock

	shr	word ptr [bp.Count+2], 1	; Make word count
	rcr	word ptr [bp.Count], 1
	jc	short MEM2_InvCount		; Odd count not allowed

		;***********************************************;
		;						;
		; The XMS Spec states that a reasonable number	;
		; of interrupt windows are guaranteed.  This	;
		; loop should be tuned to provide such.		;
		;						;
		;-----------------------------------------------;

MEM2_MoveLoop:
	mov	cx, 512				; Must be less than 8000h
	cmp	word ptr [bp.Count+2], 0	; Lots to do?
	ja	short MEM2_MaxSize
	cmp	word ptr [bp.Count], cx
	jae	short MEM2_MaxSize
	mov	cx, word ptr [bp.Count]		; Just what is left
	jcxz	short MEM2_Exit
MEM2_MaxSize:
	push	cx
	call	DoMoveBlock
	pop	cx
	jc	short MEM2_Error
	sub	word ptr [bp.Count], cx		; Subtract what we just did
	sbb	word ptr [bp.Count+2], 0
	xor	dx, dx				; Get byte count in DX:CX
	shl	cx, 1
	rcl	dx, 1
	add	word ptr [bp.SrcLinear], cx
	adc	word ptr [bp.SrcLinear+2], dx
	add	word ptr [bp.DstLinear], cx
	adc	word ptr [bp.DstLinear+2], dx
	jmp	short MEM2_MoveLoop

MEM2_Exit:
	pop	es
	pop	ds
	mov	bx, [bp.SrcHandle]		; Unlock Handles if necessary
	or	bx, bx
	jz	short NoSrcHandle
	dec	[bx.cLock]			; Unlock Source
NoSrcHandle:
	mov	bx, [bp.DstHandle]
	or	bx, bx
	jz	short NoDstHandle
	dec	[bx.cLock]			; Unlock Destination
NoDstHandle:
	popa					; Restore original registers
	mov	ax, 1
	cmp	word ptr [bp.MEReturn], 0
	jz	short MEM2_Success
	dec	ax
	mov	bl, byte ptr [bp.MEReturn]
MEM2_Success:
	mov	sp, bp				; Unwind stack
	pop	bp
	ret

MEM2_SrcError:
	cmp	bl, ERR_LENINVALID		; Invalid count
	je	short MEM2_Error		;   yes, no fiddle
	sub	bl, 2				; Convert to Source error code
	jmp	short MEM2_Error
MEM2_InvCount:
	mov	bl, ERR_LENINVALID
MEM2_Error:
	mov	byte ptr [bp.MEReturn], bl	; Pass error code through
	jmp	short MEM2_Exit

;*******************************************************************************
;
; GetLinear286
;	Convert Handle and Offset (or 0 and SEG:OFFSET) into Linear address
;	Locks Handle if necessary
;	Nested with MoveExtended286 to access local variables
;
; Entry:
;	ES:BX	Points to structure containing:
;			Handle	dw
;			Offset	dd
;	[BP.Count]	Count of bytes to move
;
; Return:
;	BX	Handle of block (0 if conventional)
;	AX:DX	Linear address
;	CARRY	=> Error
;		Error code in BL
;
; Registers Destroyed:
;	Flags, CX
;
;-------------------------------------------------------------------------------

GetLinear286	proc	near
	push	si
	push	di
	cli					; NO INTERRUPTS
	mov	si, word ptr es:[bx+2]		; Offset from start of handle
	mov	di, word ptr es:[bx+4]		; in DI:SI
	mov	bx, word ptr es:[bx]		; Handle in bx
	or	bx, bx
	jz	short GL2_Conventional

	test	[bx.Flags], USEDFLAG		; Valid Handle?
	jz	short GL2_InvHandle

	mov	ax, [bx.Len]			; Length of Block
	mov	cx, 1024
	mul	cx				; mul is faster on the 286
	sub	ax, si
	sbb	dx, di				; DX:AX = max possible count
	jc	short GL2_InvOffset		; Base past end of block
	sub	ax, word ptr [bp.Count]
	sbb	dx, word ptr [bp.Count+2]
	jc	short GL2_InvCount		; Count too big

	inc	[bx.cLock]			; Lock the Handle
	mov	ax, [bx.Base]
	mul	cx
	add	ax, si				; Linear address
	adc	dx, di				; in DX:AX

GL2_OKExit:
	clc
GL2_Exit:
	sti
	pop	di
	pop	si
	ret

GL2_Conventional:
	mov	ax, di				; Convert SEG:OFFSET into
	mov	dx, 16				; 24 bit address
	mul	dx
	add	ax, si
	adc	dx, 0				; DX:AX has base address
	mov	di, dx
	mov	si, ax
	add	si, word ptr [bp.Count]		; Get End of Block + 1 in DI:SI
	adc	di, word ptr [bp.Count+2]
	cmp	di, 010h			; 32-bit cmp
	ja	short GL2_InvCount
	jb	short GL2_OKExit
	cmp	si, 0FFF0h
	jbe	short GL2_OKExit		; Must be < 10FFEFh + 2
GL2_InvCount:
	mov	bl, ERR_LENINVALID
	jmp	short GL2_Error
GL2_InvHandle:
	mov	bl, ERR_DHINVALID		; Dest handle invalid
	jmp	short GL2_Error
GL2_InvOffset:
	mov	bl, ERR_DOINVALID		; Dest Offset invalid
GL2_Error:
	stc
	jmp	short GL2_Exit
	
GetLinear286	endp

;*******************************************************************************
;
; DoMoveBlock
;	Set up GDT and call int 15h Move Block
;	Nested within MoveExtended286
;	See 80286 programmer's reference manual for GDT entry format
;	See Int 15h documentation for Move Block function
;
; Entry:
;	CX		Word count for move
;	[BP.SrcLinear]	Linear address of the source
;	[BP.DstLinear]	Linear address of the destination
;	[BP.GDT]	GDT for Block Move
;
;	Interrupts are ON
;
; Return:
;	CARRY	=> Error
;		Error code in BL
;
; Registers Destroyed:
;	Flags, AX, CX
;
;-------------------------------------------------------------------------------
DoMoveBlock	proc	near

	push	ds

	mov	ax, ss
	mov	ds, ax
	mov	es, ax

	lea	di, [bp.GDT]
	mov	si, di				; Parameter to Block Move
	push	cx
	mov	cx, 6*8/2			; Words in the GDT
	xor	ax, ax
	rep	stosw				; Clean it out

	lea	di, [bp.GDT+2*8]		; Source Descriptor
	dec	ax				; Limit FFFFh
	stosw
	mov	ax, word ptr [bp.SrcLinear]
	stosw
	mov	al, byte ptr [bp.SrcLinear+2]
	mov	ah, 93h				; Access rights
	stosw					; Source Descriptor done

	lea	di, [bp.GDT+3*8]		; Destination Descriptor
	mov	ax, 0FFFFh			; Limit FFFFh
	stosw
	mov	ax, word ptr [bp.DstLinear]
	stosw
	mov	al, byte ptr [bp.DstLinear+2]
	mov	ah, 93h				; Access rights
	stosw					; Destination Descriptor done

	pop	cx
	mov	ah, 87h
	int	15h				; Block Move
	jc	short DMB286_Error
DMB_Exit:
	pop	ds
	ret
DMB286_Error:
	xor	bh, bh
	mov	bl, al
	mov	bl, cs:Int15Err286[bx]		   ; Pick up correct error code
	stc
	jmp	short DMB_Exit

Int15Err286	db	0, ERR_PARITY, ERR_LENINVALID, ERR_A20

DoMoveBlock	endp

MoveExtMemory	endp
