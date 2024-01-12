package erasure

import "core:bufio"
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

erasure_coder_init :: proc(N, K, w: int) -> (coder: Erasure_Coder, err: Field_Error) {
	coder.N = N
	coder.K = K
	assert(slice.contains([]int{1, 2, 4, 8}, w))
	coder.w = w
	field_n := 2
	for (1 << uint(field_n)) < (N + K) do field_n += 1
	log.debugf("field.n=%d\n", field_n)
	coder.field = field_init(field_n) or_return
	coder.encoder = matrix_init_cauchy(N, K, coder.field) or_return
	coder.chunk_size = coder.w * field_n
	log.debugf("chunk.size=%d\n", coder.chunk_size)
	coder.data_block_size = coder.chunk_size * K
	log.debugf("block.data.size=%d\n", coder.data_block_size)
	coder.code_block_size = coder.chunk_size * N
	log.debugf("block.code.size=%d\n", coder.code_block_size)
	return coder, nil
}

erasure_coder_deinit :: proc(coder: Erasure_Coder) {
	matrix_deinit(coder.encoder)
}

read_data_block :: proc(
	coder: Erasure_Coder,
	$T: typeid,
	input: io.Reader,
) -> (
	data_block: []T,
	done: bool,
	err: Erasure_Error,
) {
	block_size: int

	buffer: [size_of(T)]u8

	data_block = make([]T, coder.field.n * coder.K)

	for i in 0 ..< len(data_block) {
		read_size := io.read(input, buffer[:]) or_return
		block_size += read_size
		if read_size < len(buffer) {
			log.debugf(
				"read.last=%d < %d, wrote.buffer.size=%d\n",
				read_size,
				len(buffer),
				block_size,
			)
			buffer[len(buffer) - 1] = u8(block_size)
		}
		data_block[i] = transmute(T)buffer
	}

	return data_block, block_size < coder.data_block_size, nil
}

read_code_block :: proc(
	coder: Erasure_Coder,
	$T: typeid,
	inputs: []bufio.Reader,
) -> (
	code_block: []T,
	done: bool,
	err: Erasure_Error,
) {
	buffer: [size_of(T)]u8

	code_block = make([]T, coder.field.n * coder.K)

	fmt.println("reading")
	for i in 0 ..< len(code_block) {
		read_size := bufio.reader_read(
			&inputs[math.floor_div(i, coder.field.n)],
			buffer[:],
		) or_return
		fmt.printf("read[%d]=%d\n", i, read_size)
		assert(read_size == len(buffer))
		code_block[i] = transmute(T)buffer
	}

	fmt.println("peeking")
	p := math.floor_div(len(code_block) - 1, coder.field.n)
	// peek_reader: bufio.Lookahead_Reader
	peek_buffer: [1]u8
	// bufio.lookahead_reader_init(&peek_reader, inputs[p], peek_buffer[:])
	// peek := bufio.lookahead_reader_peek(&peek_reader, 1) or_return
	_, io_err := bufio.reader_peek(&inputs[p], 1)
	if io_err == io.Error.No_Progress {
		done = true
	}
	return code_block, done, nil
}

write_code_block :: proc(
	coder: Erasure_Coder,
	$T: typeid,
	encoder: Finite_Field_Matrix,
	data_block: []T,
	outputs: []io.Writer,
) -> (
	err: Erasure_Error,
) {
	code_block := make([]T, coder.field.n * coder.N)
	defer delete(code_block)

	for i in 0 ..< len(code_block) {
		for j in 0 ..< encoder.num_cols {
			if matrix_get(encoder, i, j) == 1 {
				code_block[i] ~= data_block[j]
			}
		}
		buffer := transmute([size_of(T)]u8)code_block[i]
		io.write(outputs[math.floor_div(i, coder.field.n)], buffer[:]) or_return
	}
	return nil
}

write_data_block :: proc(
	coder: Erasure_Coder,
	$T: typeid,
	decoder: Finite_Field_Matrix,
	code_block: []T,
	output: io.Writer,
	done: bool,
) -> (
	data_block_size: int,
	err: Erasure_Error,
) {
	out_buffer := make([][]u8, coder.field.n * coder.K)
	// defer for b in out_buffer do delete(b)
	defer delete(out_buffer)

	data_block := make([]T, coder.field.n * coder.K)
	defer delete(data_block)

	for i in 0 ..< len(data_block) {
		for j in 0 ..< decoder.num_cols {
			if matrix_get(decoder, i, j) == 1 {
				data_block[i] ~= code_block[j]
			}
		}
		buffer := transmute([size_of(T)]u8)data_block[i]
		out_buffer[i] = buffer[:]
	}
	if done {
		data_block_size = int(out_buffer[len(out_buffer) - 1][len(out_buffer[0]) - 1])
		log.debugf("last:block.data.size=%d < %d\n", data_block_size, coder.data_block_size)
		assert(data_block_size < coder.data_block_size)
	} else {
		data_block_size = coder.data_block_size
	}
	written_size := 0
	for i in 0 ..< len(out_buffer) {
		if (written_size + coder.w) <= data_block_size {
			io.write(output, out_buffer[i]) or_return
			written_size += coder.w
		} else {
			io.write(output, out_buffer[i][:(data_block_size - written_size)]) or_return
			written_size = data_block_size
			break
		}
	}

	return data_block_size, nil
}

encode :: proc(
	coder: Erasure_Coder,
	$T: typeid,
	input: io.Reader,
	outputs: []io.Writer,
) -> (
	size: int,
	err: Erasure_Error,
) {
	assert(size_of(T) == coder.w)
	assert(len(outputs) == coder.N)

	encoder_bin := matrix_to_binary(coder.encoder) or_return
	defer matrix_deinit(encoder_bin)

	done: bool
	for !done {
		data_block, is_done := read_data_block(coder, T, input) or_return
		defer delete(data_block)

		done = is_done
		write_code_block(coder, T, encoder_bin, data_block, outputs)
		if !done {
			size += coder.data_block_size
		} else {
			buffer := transmute([size_of(T)]u8)data_block[len(data_block) - 1]
			size += int(buffer[len(buffer) - 1])
		}
	}

	return size, nil
}

decode :: proc(
	coder: Erasure_Coder,
	$T: typeid,
	excluded_shards: []int,
	inputs: []io.Reader,
	output: io.Writer,
) -> (
	size: int,
	err: Erasure_Error,
) {
	assert(size_of(T) == coder.w)
	assert(len(excluded_shards) == (coder.N - coder.K))
	assert(len(inputs) == coder.K)

	sub := matrix_submatrix(coder.encoder, excluded_shards, {})
	defer matrix_deinit(sub)
	inv := matrix_invert(sub) or_return
	defer matrix_deinit(inv)
	decoder_bin := matrix_to_binary(inv) or_return
	defer matrix_deinit(decoder_bin)

	peek_readers := make([]bufio.Reader, len(inputs))
	defer delete(peek_readers)
	// peek_readers := make([]bufio.Lookahead_Reader, len(inputs))
	// defer delete(peek_readers)
	// peek_buf := make([][bufio.DEFAULT_BUF_SIZE]u8, len(inputs))
	// defer delete(peek_buf)

	for s, i in inputs {
		bufio.reader_init(&peek_readers[i], inputs[i])
	}
	defer for &r in peek_readers do bufio.reader_destroy(&r)
	done: bool
	for !done {
		// code_block, is_done := read_code_block(coder, T, peek_readers) or_return
		code_block, is_done := read_code_block(coder, T, peek_readers) or_return
		defer delete(code_block)
		done = is_done
		size += write_data_block(coder, T, decoder_bin, code_block, output, done) or_return
	}
	return size, nil
}

