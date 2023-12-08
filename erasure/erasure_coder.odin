package erasure

import "core:fmt"
import "core:log"
import "core:math"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"

Erasure_Coder :: struct {
	N:               int,
	K:               int,
	w:               int,
	field:           Binary_Finite_Field,
	encoder:         Finite_Field_Matrix,
	chunk_size:      int,
	data_block_size: int,
	code_block_size: int,
}

init_erasure_coder :: proc(N, K, w: int) -> (coder: Erasure_Coder, err: Field_Error) {
	coder.N = N
	coder.K = K
	assert(slice.contains([]int{1, 2, 4, 8}, w))
	coder.w = w
	field_n := 2
	for (1 << uint(field_n)) < (N + K) do field_n += 1
	coder.field = field_init(field_n) or_return
	coder.encoder = matrix_init_cauchy(N, K, coder.field) or_return
	coder.chunk_size = coder.w * field_n
	coder.data_block_size = coder.chunk_size * K
	coder.code_block_size = coder.chunk_size * N
	return coder, nil
}

