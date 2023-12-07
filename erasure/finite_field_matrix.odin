package erasure

import "core:fmt"
import "core:log"
import "core:math"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:testing"

Finite_Field_Matrix :: struct {
	field:    Binary_Finite_Field,
	rows:     int,
	cols:     int,
	elements: [][]int,
}

matrix_init :: proc(
	rows, cols: int,
	n: int,
) -> (
	ffm: Finite_Field_Matrix,
	err: Field_Error,
) {
	ffm.field = field_init(n) or_return
	ffm.rows = rows
	ffm.cols = cols
	ffm.elements = make([][]int, cols)
	for c := 0; c < cols; c += 1 {
		ffm.elements[c] = make([]int, rows)
	}
	return ffm, nil
}

matrix_deinit :: proc(ffm: Finite_Field_Matrix) {
	for c := 0; c < ffm.cols; c += 1 {
		delete(ffm.elements[c])
	}
	delete(ffm.elements)
}

matrix_num_rows :: proc(ffm: Finite_Field_Matrix) -> int {
	return len(ffm.elements[0])
}

matrix_num_cols :: proc(ffm: Finite_Field_Matrix) -> int {
	return len(ffm.elements)
}

matrix_get :: proc(ffm: Finite_Field_Matrix, r, c: int) -> int {
	return ffm.elements[c][r]
}

matrix_set :: proc(ffm: Finite_Field_Matrix, r, c: int, v: int) {
	ffm.elements[c][r] = v
}

matrix_display :: proc(ffm: Finite_Field_Matrix) {
	fmt.print("matrix[")
	for r := 0; r < ffm.rows; r += 1 {
		for c := 0; c < ffm.cols; c += 1 {
			fmt.print(matrix_get(ffm, r, c))
			if c < ffm.cols - 1 {
				fmt.print(", ")
			} else if r < ffm.rows - 1 {
				fmt.print("; ")
			}
		}
	}
	fmt.println("]")
}

@(test)
test_matrix_display :: proc(t: ^testing.T) {
	m, err := matrix_init(4, 5, 3)
	defer matrix_deinit(m)
	v := 1
	for i := 0; i < m.rows; i += 1 {
		for j := 0; j < m.cols; j += 1 {
			matrix_set(m, i, j, v)
			v += 1
		}
	}
	matrix_display(m)
}
