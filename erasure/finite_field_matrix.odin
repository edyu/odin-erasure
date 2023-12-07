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

matrix_set_cauchy :: proc(ffm: Finite_Field_Matrix) -> Field_Error {
	assert(ffm.field.order >= ffm.rows + ffm.cols)
	for r := 0; r < ffm.rows; r += 1 {
		for c := 0; c < ffm.cols; c += 1 {
			matrix_set(
				ffm,
				r,
				c,
				field_invert(
					ffm.field,
					field_subtract(ffm.field, r + ffm.cols, c),
				) or_return,
			)
		}
	}
	return nil
}

matrix_submatrix :: proc(
	ffm: Finite_Field_Matrix,
	excluded_rows: bit_set[0 ..= 9],
	excluded_cols: bit_set[0 ..= 9],
) -> (
	sub: Finite_Field_Matrix,
	err: Field_Error,
) {
	sub_rows := ffm.rows - card(excluded_rows)
	sub_cols := ffm.cols - card(excluded_cols)
	sub = matrix_init(sub_rows, sub_cols, ffm.field.n) or_return
	i := 0
	for r := 0; r < ffm.rows; r += 1 {
		if r in excluded_rows do continue
		j := 0
		for c := 0; c < ffm.cols; c += 1 {
			if c in excluded_cols do continue
			matrix_set(sub, i, j, matrix_get(ffm, r, c))
			j += 1
		}
		i += 1
	}
	return sub, nil
}

matrix_determinant :: proc(
	ffm: Finite_Field_Matrix,
) -> (
	det: int,
	err: Field_Error,
) {
	assert(ffm.rows == ffm.cols)

	switch ffm.rows {
	case 1:
		return matrix_get(ffm, 0, 0), nil
	// case 2:
	// 	return determinant(matrix_to_matrix2x2(ffm)), nil
	// case 3:
	// 	return determinant(matrix_to_matrix3x3(ffm)), nil
	// case 4:
	// 	return determinant(matrix_to_matrix4x4(ffm)), nil
	case:
		for c := 0; c < ffm.cols; c += 1 {
			sub := matrix_submatrix(ffm, {0}, {c}) or_return
			defer matrix_deinit(sub)
			sub_det := matrix_determinant(sub) or_return
			x := field_multiply(ffm.field, matrix_get(ffm, 0, c), sub_det)

			if c % 2 == 1 {
				x = field_negate(ffm.field, x)
			}
			det = field_add(ffm.field, det, x)
		}
		return det, nil
	}
}

matrix_cofactors :: proc(
	ffm: Finite_Field_Matrix,
) -> (
	cof: Finite_Field_Matrix,
	err: Field_Error,
) {
	assert(ffm.rows == ffm.cols)

	cof = matrix_init(ffm.rows, ffm.cols, ffm.field.n) or_return
	for r := 0; r < ffm.rows; r += 1 {
		for c := 0; c < ffm.cols; c += 1 {
			sub := matrix_submatrix(ffm, {r}, {c}) or_return
			defer matrix_deinit(sub)
			sub_det := matrix_determinant(sub) or_return
			if (r + c) % 2 != 1 {
				matrix_set(cof, r, c, sub_det)
			} else {
				matrix_set(
					cof,
					r,
					c,
					field_negate(ffm.field, sub_det)
				)
			}
		}
	}
	return cof, nil
}

matrix_transpose :: proc(
	ffm: Finite_Field_Matrix,
) -> (
	m: Finite_Field_Matrix,
	err: Field_Error,
) {
	assert(ffm.rows == ffm.cols)

	m = matrix_init(ffm.rows, ffm.cols, ffm.field.n) or_return
	for r := 0; r < ffm.rows; r += 1 {
		for c := 0; c < ffm.cols; c += 1 {
			matrix_set(m, r, c, matrix_get(ffm, c, r))
		}
	}

	return m, nil
}

matrix_scale :: proc(
	ffm: Finite_Field_Matrix,
	factor: int,
) -> (
	m: Finite_Field_Matrix,
	err: Field_Error,
) {
	assert(ffm.rows == ffm.cols)

	m = matrix_init(ffm.rows, ffm.cols, ffm.field.n) or_return
	for r := 0; r < ffm.rows; r += 1 {
		for c := 0; c < ffm.cols; c += 1 {
			matrix_set(m, r, c, field_multiply(ffm.field, matrix_get(ffm, c, r), factor))
		}
	}

	return m, nil
}

matrix_invert :: proc(
	ffm: Finite_Field_Matrix,
) -> (
	m: Finite_Field_Matrix,
	err: Field_Error,
) {
	cof := matrix_cofactors(ffm) or_return
	defer matrix_deinit(cof)
	xps := matrix_transpose(cof) or_return
	defer matrix_deinit(xps)
	det := matrix_determinant(ffm) or_return
	return matrix_scale(xps, field_invert(ffm.field, det) or_return)
}

matrix_multiply :: proc(
	ffm: Finite_Field_Matrix,
	mff: Finite_Field_Matrix,
) -> (
	m: Finite_Field_Matrix,
	err: Field_Error,
) {
	assert(ffm.cols == mff.cols)

	m = matrix_init(ffm.rows, mff.cols, ffm.field.n) or_return
	for r := 0; r < ffm.rows; r += 1 {
		for c := 0; c < mff.cols; c += 1 {
			for i := 0; i < ffm.cols; i += 1 {
				x := matrix_get(m, r, c)
				y := matrix_get(ffm, r, i)
				z := matrix_get(mff, i, c)
				matrix_set(m, r, c, field_add(ffm.field, x, field_multiply(ffm.field, y, z)))
			}
		}
	}

	return m, nil
}

matrix_binary_rep :: proc(
	ffm: Finite_Field_Matrix,
)-> (
	m: Finite_Field_Matrix,
	err: Field_Error,
) {
	m = matrix_init(ffm.rows * ffm.field.n, ffm.cols * ffm.field.n, 1) or_return
	for r := 0; r < ffm.rows; r += 1 {
		for c := 0; c < ffm.cols; c += 1 {
			a := matrix_get(ffm, r, c)
			mat_a := field_matrix(ffm.field, a)
			defer for i := 0; i < ffm.field.n; i += 1 do delete(mat_a[i])
			defer delete(mat_a)
			for i := 0; i < ffm.field.n; i += 1 {
				for j := 0; j < ffm.field.n; j += 1 {
					matrix_set(m, r * ffm.field.n + i, c * ffm.field.n + j, field_validate(ffm.field, mat_a[j][i]))
				}
			}
		}
	}
	return m, nil
}

matrix_to_matrix2x2 :: proc(ffm: Finite_Field_Matrix) -> (m: matrix[2, 2]int) {
	assert(ffm.cols == ffm.rows)
	assert(ffm.rows == 2)

	for r := 0; r < ffm.rows; r += 1 {
		for c := 0; c < ffm.cols; c += 1 {
			m[r, c] = matrix_get(ffm, r, c)
		}
	}
	return m
}

matrix_to_matrix3x3 :: proc(ffm: Finite_Field_Matrix) -> (m: matrix[3, 3]int) {
	assert(ffm.cols == ffm.rows)
	assert(ffm.rows == 3)

	for r := 0; r < ffm.rows; r += 1 {
		for c := 0; c < ffm.cols; c += 1 {
			m[r, c] = matrix_get(ffm, r, c)
		}
	}
	return m
}

matrix_to_matrix4x4 :: proc(ffm: Finite_Field_Matrix) -> (m: matrix[4, 4]int) {
	assert(ffm.cols == ffm.rows)
	assert(ffm.rows == 4)

	for r := 0; r < ffm.rows; r += 1 {
		for c := 0; c < ffm.cols; c += 1 {
			m[r, c] = matrix_get(ffm, r, c)
		}
	}
	return m
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

@(test)
test_matrix_set_cauchy :: proc(t: ^testing.T) {
	m, err := matrix_init(5, 3, 3)
	defer matrix_deinit(m)
	matrix_set_cauchy(m)
	matrix_display(m)
}

@(test)
test_matrix_determinant :: proc(t: ^testing.T) {
	m, err := matrix_init(2, 2, 2)
	defer matrix_deinit(m)
	matrix_set_cauchy(m)
	matrix_display(m)
	det: int
	det, err = matrix_determinant(m)
	testing.expect(
		t,
		det == 1,
		fmt.tprintf("expected det: %v, got %v", 5, det),
	)
	m2: Finite_Field_Matrix
	m2, err = matrix_init(3, 3, 3)
	defer matrix_deinit(m2)
	matrix_set_cauchy(m2)
	matrix_display(m2)
	det, err = matrix_determinant(m2)
	testing.expect(
		t,
		det == 7,
		fmt.tprintf("expected det: %v, got %v", 7, det),
	)
	m3: Finite_Field_Matrix
	m3, err = matrix_init(4, 4, 4)
	defer matrix_deinit(m3)
	matrix_set_cauchy(m3)
	matrix_display(m3)
	det, err = matrix_determinant(m3)
	testing.expect(
		t,
		det == 7,
		fmt.tprintf("expected det: %v, got %v", 7, det),
	)
}
