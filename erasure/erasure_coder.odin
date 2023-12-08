package erasure

import "core:fmt"
import "core:io"
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

read_data_block :: proc(
	coder: Erasure_Coder,
	$T: typeid,
	in_fifo: io.Reader,
) -> (
	block_ints: []T,
	done: bool,
	err: Erasure_Error,
) {
	block_size: int

	buffer := make([]u8, coder.w)
	defer delete(buffer)

	block_ints = make([]T, coder.field.n * coder.K)

	for i in 0 ..< len(block_ints) {
		// read_size := read(in_fifo, &buffer) or_return
		read_size := 0
		block_size += read_size
		if read_size < len(buffer) {
			buffer[len(buffer) - 1] = u8(block_size)
		}
		block_ints[i] = transmute(T)buffer
	}

	return block_ints, block_size < coder.data_block_size, nil
}

read_code_block :: proc(
	coder: Erasure_Coder,
	$T: typeid,
	in_fifos: []io.Reader,
) -> (
	block_ints: []T,
	done: bool,
	err: Erasure_Error,
) {
	buffer := make([]u8, coder.w)
	defer delete(buffer)

	block_ints = make([]T, coder.field.n * coder.K)

	for i in 0 ..< len(block_ints) {
		// read_size := read(in_fifos[math.floor_div(i, coder.field.n)], &buffer) or_return
		read_size := 0
		assert(read_size == len(buffer))
		block_ints[i] = transmute(T)buffer
	}

	// return block_ints,
	// 	len(in_fifos[math.floor_div(len(block_ints) - 1, coder.field.n)].peek(1)) == 0,
	// 	nil
	return block_ints, false, nil
}

write_code_block :: proc(
	coder: Erasure_Coder,
	$T: typeid,
	encoder: Finite_Field_Matrix,
	data_block_ints: []T,
	out_fifos: []io.Writer,
) -> (
	err: Erasure_Error,
) {
	code_block_ints := make([]T, coder.field.n * coder.N)
	defer delete(code_block_ints)

	for i in 0 ..< len(code_block_ints) {
		for j in 0 ..< encoder.num_cols {
			if matrix_get(encoder, i, j) == 1 {
				code_block_ints[i] ~= data_block_ints[j]
			}
		}
		int_buffer: []u8 = make([]u8, coder.w)
		defer delete(int_buffer)
		switch coder.w {
		case 1:
			int_buffer = transmute([1]u8)code_block_ints[i]
		case 2:
			int_buffer = transmute([2]u8)code_block_ints[i]
		case 4:
			int_buffer = transmute([4]u8)code_block_ints[i]
		case 8:
			int_buffer = transmute([8]u8)code_block_ints[i]
		}
		// write(out_fifos[math.floor_div(i, coder.field.n)], out_buffer) or_return
	}
	return nil
}

write_data_block :: proc(
	coder: Erasure_Coder,
	$T: typeid,
	decoder: Finite_Field_Matrix,
	code_block_ints: []T,
	out_fifo: io.Writer,
	done: bool,
) -> (
	data_block_size: int,
	err: Erasure_Error,
) {
	out_buffer: [][]u8 = make([][]u8, coder.field.n * coder.K)
	defer for i in out_buffer do delete(out_buffer[i])
	defer delete(out_buffer)

	data_block_ints := make([]T, coder.field.n * coder.K)
	defer delete(data_block_ints)

	for i in 0 ..< len(data_block_ints) {
		for j in 0 ..< decoder.num_cols {
			if matrix_get(decoder, i, j) == 1 {
				data_block_ints[i] ~= code_block_ints[j]
			}
		}
		int_buffer: []u8 = make([]u8, coder.w)
		switch coder.w {
		case 1:
			int_buffer = transmute([1]u8)data_block_ints[i]
		case 2:
			int_buffer = transmute([2]u8)data_block_ints[i]
		case 4:
			int_buffer = transmute([4]u8)data_block_ints[i]
		case 8:
			int_buffer = transmute([8]u8)data_block_ints[i]
		}
		append(&out_buffer[i], int_buffer)
	}
	if done {
		data_block_size = out_buffer[len(out_buffer) - 1][len(out_buffer[0]) - 1]
		assert(data_block_size < coder.data_block_size)
	} else {
		data_block_size = coder.data_block_size
	}
	written_size := 0
	for i in 0 ..< len(out_buffer) {
		if (written_size + coder.w) <= data_block_size {
			// write(out_fifo, out_buffer[i]) or_return
			written_size += coder.w
		} else {
			// write(out_fifo, out_buffer[i][:(data_block_size - written_size)])
			written_size = data_block_size
			break
		}
	}

	return data_block_size, nil
}

encode :: proc(
	coder: Erasure_Coder,
	$T: typeid,
	in_fifo: io.Reader,
	out_fifos: []io.Writer,
) -> (
	size: int,
	err: Erasure_Error,
) {
	assert(len(out_fifos) == coder.N)

	encoder_bin := matrix_binary_rep(coder.encoder) or_return

	done: bool
	for !done {
		data_block_ints, is_done := read_data_block(coder, T, in_fifo) or_return
		done = is_done
		write_code_block(coder, T, encoder_bin, data_block_ints, out_fifos)
		if !done {
			size += coder.data_block_size
		} else {
			buffer := make([]u8, coder.w)
			switch coder.w {
			case 1:
				buffer = transmute([1]u8)data_block_ints[len(data_block_ints) - 1]
			case 2:
				buffer = transmute([2]u8)data_block_ints[len(data_block_ints) - 1]
			case 4:
				buffer = transmute([4]u8)data_block_ints[len(data_block_ints) - 1]
			case 8:
				buffer = transmute([8]u8)data_block_ints[len(data_block_ints) - 1]
			}
			size += buffer[len(buffer) - 1]
		}
	}

	return size, nil
}

decode :: proc(
	coder: Erasure_Coder,
	$T: typeid,
	excluded_shards: []int,
	in_fifos: []io.Reader,
	out_fifo: io.Writer,
) -> (
	size: int,
	err: Erasure_Error,
) {
	assert(len(excluded_shards) == (coder.N - coder.K))
	assert(len(in_fifos) == coder.K)

	sub := matrix_submatrix(coder.encoder, excluded_shards, {})
	defer matrix_deinit(sub)
	inv := matrix_invert(sub) or_return
	defer matrix_deinit(inv)
	decoder_bin := matrix_binary_rep(inv) or_return

	done: bool
	for !done {
		code_block_ints, is_done := read_code_block(coder, T, in_fifos) or_return
		done = is_done
		size += write_data_block(coder, T, decoder_bin, code_block_ints, out_fifo, done) or_return
	}
	return size, nil
}

