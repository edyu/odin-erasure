package erasure

import "core:fmt"
import "core:log"
import "core:math"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:testing"

Finite_Field_Matrix :: struct {
	field:    Binary_Finite_Field,
	num_rows: int,
	num_cols: int,
	elements: [][]int,
}

matrix_init :: proc(
	num_rows, num_cols: int,
	n: int,
) -> (
	ffm: Finite_Field_Matrix,
	err: Field_Error,
) {
	ffm.field = field_init(n) or_return
	ffm.num_rows = num_rows
	ffm.num_cols = num_cols
	ffm.elements = make([][]int, num_cols)
	for c := 0; c < num_cols; c += 1 {
		ffm.elements[c] = make([]int, num_rows)
	}
	return ffm, nil
}

matrix_deinit :: proc(ffm: Finite_Field_Matrix) {
	for c := 0; c < ffm.num_cols; c += 1 {
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
	for r := 0; r < ffm.num_rows; r += 1 {
		for c := 0; c < ffm.num_cols; c += 1 {
			fmt.print(matrix_get(ffm, r, c))
			if c < ffm.num_cols - 1 {
				fmt.print(", ")
			} else if r < ffm.num_rows - 1 {
				fmt.print("; ")
			}
		}
	}
	fmt.println("]")
}

matrix_set_cauchy :: proc(ffm: Finite_Field_Matrix) -> Field_Error {
	assert(ffm.field.order >= ffm.num_rows + ffm.num_cols)
	for r := 0; r < ffm.num_rows; r += 1 {
		for c := 0; c < ffm.num_cols; c += 1 {
			matrix_set(
				ffm,
				r,
				c,
				field_invert(ffm.field, field_subtract(ffm.field, r + ffm.num_cols, c)) or_return,
			)
		}
	}
	return nil
}

matrix_submatrix :: proc(
	ffm: Finite_Field_Matrix,
	excluded_num_rows: []int,
	excluded_num_cols: []int,
) -> (
	sub: Finite_Field_Matrix,
	err: Field_Error,
) {
	sub_num_rows := ffm.num_rows - len(excluded_num_rows)
	sub_num_cols := ffm.num_cols - len(excluded_num_cols)
	sub = matrix_init(sub_num_rows, sub_num_cols, ffm.field.n) or_return
	i := 0
	for r := 0; r < ffm.num_rows; r += 1 {
		if slice.contains(excluded_num_rows, r) do continue
		j := 0
		for c := 0; c < ffm.num_cols; c += 1 {
			if slice.contains(excluded_num_cols, c) do continue
			matrix_set(sub, i, j, matrix_get(ffm, r, c))
			j += 1
		}
		i += 1
	}
	return sub, nil
}

matrix_determinant :: proc(ffm: Finite_Field_Matrix) -> (det: int, err: Field_Error) {
	assert(ffm.num_rows == ffm.num_cols)

	switch ffm.num_rows {
	case 1:
		return matrix_get(ffm, 0, 0), nil
	case:
		for c := 0; c < ffm.num_cols; c += 1 {
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
	assert(ffm.num_rows == ffm.num_cols)

	cof = matrix_init(ffm.num_rows, ffm.num_cols, ffm.field.n) or_return
	for r := 0; r < ffm.num_rows; r += 1 {
		for c := 0; c < ffm.num_cols; c += 1 {
			sub := matrix_submatrix(ffm, {r}, {c}) or_return
			defer matrix_deinit(sub)
			sub_det := matrix_determinant(sub) or_return
			if (r + c) % 2 != 1 {
				matrix_set(cof, r, c, sub_det)
			} else {
				matrix_set(cof, r, c, field_negate(ffm.field, sub_det))
			}
		}
	}
	return cof, nil
}

matrix_transpose :: proc(ffm: Finite_Field_Matrix) -> (m: Finite_Field_Matrix, err: Field_Error) {
	assert(ffm.num_rows == ffm.num_cols)

	m = matrix_init(ffm.num_rows, ffm.num_cols, ffm.field.n) or_return
	for r := 0; r < ffm.num_rows; r += 1 {
		for c := 0; c < ffm.num_cols; c += 1 {
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
	assert(ffm.num_rows == ffm.num_cols)

	m = matrix_init(ffm.num_rows, ffm.num_cols, ffm.field.n) or_return
	for r := 0; r < ffm.num_rows; r += 1 {
		for c := 0; c < ffm.num_cols; c += 1 {
			matrix_set(m, r, c, field_multiply(ffm.field, matrix_get(ffm, r, c), factor))
		}
	}

	return m, nil
}

matrix_invert :: proc(ffm: Finite_Field_Matrix) -> (m: Finite_Field_Matrix, err: Field_Error) {
	cof := matrix_cofactors(ffm) or_return
	defer matrix_deinit(cof)
	txp := matrix_transpose(cof) or_return
	defer matrix_deinit(txp)
	det := matrix_determinant(ffm) or_return
	return matrix_scale(txp, field_invert(ffm.field, det) or_return)
}

matrix_multiply :: proc(
	ffm: Finite_Field_Matrix,
	mff: Finite_Field_Matrix,
) -> (
	m: Finite_Field_Matrix,
	err: Field_Error,
) {
	assert(ffm.num_cols == mff.num_cols)

	m = matrix_init(ffm.num_rows, mff.num_cols, ffm.field.n) or_return
	for r := 0; r < ffm.num_rows; r += 1 {
		for c := 0; c < mff.num_cols; c += 1 {
			for i := 0; i < ffm.num_cols; i += 1 {
				x := matrix_get(m, r, c)
				y := matrix_get(ffm, r, i)
				z := matrix_get(mff, i, c)
				matrix_set(m, r, c, field_add(ffm.field, x, field_multiply(ffm.field, y, z)))
			}
		}
	}

	return m, nil
}

matrix_binary_rep :: proc(ffm: Finite_Field_Matrix) -> (m: Finite_Field_Matrix, err: Field_Error) {
	m = matrix_init(ffm.num_rows * ffm.field.n, ffm.num_cols * ffm.field.n, 1) or_return
	for r := 0; r < ffm.num_rows; r += 1 {
		for c := 0; c < ffm.num_cols; c += 1 {
			a := matrix_get(ffm, r, c)
			mat_a := field_matrix(ffm.field, a)
			defer for i := 0; i < ffm.field.n; i += 1 do delete(mat_a[i])
			defer delete(mat_a)
			for i := 0; i < ffm.field.n; i += 1 {
				for j := 0; j < ffm.field.n; j += 1 {
					matrix_set(
						m,
						r * ffm.field.n + i,
						c * ffm.field.n + j,
						field_validate(ffm.field, mat_a[j][i]),
					)
				}
			}
		}
	}
	return m, nil
}

@(test)
test_matrix_display :: proc(t: ^testing.T) {
	m, err := matrix_init(4, 5, 3)
	defer matrix_deinit(m)
	v := 1
	for i := 0; i < m.num_rows; i += 1 {
		for j := 0; j < m.num_cols; j += 1 {
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

	testing.expect(
		t,
		matrix_get(m, 0, 0) == 6,
		fmt.tprintf("expected 6: %v, got %v", 6, matrix_get(m, 0, 0)),
	)
	testing.expect(
		t,
		matrix_get(m, 0, 1) == 5,
		fmt.tprintf("expected 5: %v, got %v", 5, matrix_get(m, 0, 1)),
	)
	testing.expect(
		t,
		matrix_get(m, 0, 2) == 1,
		fmt.tprintf("expected 1: %v, got %v", 1, matrix_get(m, 0, 2)),
	)
	testing.expect(
		t,
		matrix_get(m, 1, 0) == 7,
		fmt.tprintf("expected 7: %v, got %v", 7, matrix_get(m, 1, 0)),
	)
	testing.expect(
		t,
		matrix_get(m, 1, 1) == 2,
		fmt.tprintf("expected 2: %v, got %v", 2, matrix_get(m, 1, 1)),
	)
	testing.expect(
		t,
		matrix_get(m, 1, 2) == 3,
		fmt.tprintf("expected 3: %v, got %v", 3, matrix_get(m, 1, 2)),
	)
	testing.expect(
		t,
		matrix_get(m, 2, 0) == 2,
		fmt.tprintf("expected 2: %v, got %v", 2, matrix_get(m, 2, 0)),
	)
	testing.expect(
		t,
		matrix_get(m, 2, 1) == 7,
		fmt.tprintf("expected 7: %v, got %v", 7, matrix_get(m, 2, 1)),
	)
	testing.expect(
		t,
		matrix_get(m, 2, 2) == 4,
		fmt.tprintf("expected 4: %v, got %v", 4, matrix_get(m, 2, 2)),
	)
	testing.expect(
		t,
		matrix_get(m, 3, 0) == 3,
		fmt.tprintf("expected 3: %v, got %v", 3, matrix_get(m, 3, 0)),
	)
	testing.expect(
		t,
		matrix_get(m, 3, 1) == 4,
		fmt.tprintf("expected 4: %v, got %v", 4, matrix_get(m, 3, 1)),
	)
	testing.expect(
		t,
		matrix_get(m, 3, 2) == 7,
		fmt.tprintf("expected 7: %v, got %v", 7, matrix_get(m, 3, 2)),
	)
	testing.expect(
		t,
		matrix_get(m, 4, 0) == 4,
		fmt.tprintf("expected 4: %v, got %v", 4, matrix_get(m, 4, 0)),
	)
	testing.expect(
		t,
		matrix_get(m, 4, 1) == 3,
		fmt.tprintf("expected 3: %v, got %v", 3, matrix_get(m, 4, 1)),
	)
	testing.expect(
		t,
		matrix_get(m, 4, 2) == 2,
		fmt.tprintf("expected 2: %v, got %v", 2, matrix_get(m, 4, 2)),
	)
}

@(test)
test_matrix_submatrix :: proc(t: ^testing.T) {
	i, _ := matrix_init(5, 3, 3)
	defer matrix_deinit(i)
	matrix_set_cauchy(i)

	m, _ := matrix_submatrix(i, {0, 1}, {})
	defer matrix_deinit(m)

	testing.expect(
		t,
		matrix_get(m, 0, 0) == 2,
		fmt.tprintf("expected 2: %v, got %v", 2, matrix_get(m, 0, 0)),
	)
	testing.expect(
		t,
		matrix_get(m, 0, 1) == 7,
		fmt.tprintf("expected 7: %v, got %v", 7, matrix_get(m, 0, 1)),
	)
	testing.expect(
		t,
		matrix_get(m, 0, 2) == 4,
		fmt.tprintf("expected 4: %v, got %v", 4, matrix_get(m, 0, 2)),
	)
	testing.expect(
		t,
		matrix_get(m, 1, 0) == 3,
		fmt.tprintf("expected 3: %v, got %v", 3, matrix_get(m, 1, 0)),
	)
	testing.expect(
		t,
		matrix_get(m, 1, 1) == 4,
		fmt.tprintf("expected 4: %v, got %v", 4, matrix_get(m, 1, 1)),
	)
	testing.expect(
		t,
		matrix_get(m, 1, 2) == 7,
		fmt.tprintf("expected 7: %v, got %v", 7, matrix_get(m, 1, 2)),
	)
	testing.expect(
		t,
		matrix_get(m, 2, 0) == 4,
		fmt.tprintf("expected 4: %v, got %v", 4, matrix_get(m, 2, 0)),
	)
	testing.expect(
		t,
		matrix_get(m, 2, 1) == 3,
		fmt.tprintf("expected 3: %v, got %v", 3, matrix_get(m, 2, 1)),
	)
	testing.expect(
		t,
		matrix_get(m, 2, 2) == 2,
		fmt.tprintf("expected 2: %v, got %v", 2, matrix_get(m, 2, 2)),
	)
}

@(test)
test_matrix_cofactors :: proc(t: ^testing.T) {
	i, _ := matrix_init(5, 3, 3)
	defer matrix_deinit(i)
	matrix_set_cauchy(i)

	s, _ := matrix_submatrix(i, {0, 1}, {})
	defer matrix_deinit(s)

	m, _ := matrix_cofactors(s)
	defer matrix_deinit(m)

	testing.expect(
		t,
		matrix_get(m, 0, 0) == 1,
		fmt.tprintf("expected 1: %v, got %v", 1, matrix_get(m, 0, 0)),
	)
	testing.expect(
		t,
		matrix_get(m, 0, 1) == 7,
		fmt.tprintf("expected 7: %v, got %v", 7, matrix_get(m, 0, 1)),
	)
	testing.expect(
		t,
		matrix_get(m, 0, 2) == 3,
		fmt.tprintf("expected 3: %v, got %v", 3, matrix_get(m, 0, 2)),
	)
	testing.expect(
		t,
		matrix_get(m, 1, 0) == 2,
		fmt.tprintf("expected 2: %v, got %v", 2, matrix_get(m, 1, 0)),
	)
	testing.expect(
		t,
		matrix_get(m, 1, 1) == 2,
		fmt.tprintf("expected 2: %v, got %v", 2, matrix_get(m, 1, 1)),
	)
	testing.expect(
		t,
		matrix_get(m, 1, 2) == 7,
		fmt.tprintf("expected 7: %v, got %v", 7, matrix_get(m, 1, 2)),
	)
	testing.expect(
		t,
		matrix_get(m, 2, 0) == 5,
		fmt.tprintf("expected 5: %v, got %v", 5, matrix_get(m, 2, 0)),
	)
	testing.expect(
		t,
		matrix_get(m, 2, 1) == 2,
		fmt.tprintf("expected 2: %v, got %v", 2, matrix_get(m, 2, 1)),
	)
	testing.expect(
		t,
		matrix_get(m, 2, 2) == 1,
		fmt.tprintf("expected 1: %v, got %v", 1, matrix_get(m, 2, 2)),
	)
}

@(test)
test_matrix_inverse :: proc(t: ^testing.T) {
	i, _ := matrix_init(5, 3, 3)
	defer matrix_deinit(i)
	matrix_set_cauchy(i)

	s, _ := matrix_submatrix(i, {0, 1}, {})
	defer matrix_deinit(s)

	m, _ := matrix_invert(s)
	defer matrix_deinit(m)

	testing.expect(
		t,
		matrix_get(m, 0, 0) == 3,
		fmt.tprintf("expected 3: %v, got %v", 3, matrix_get(m, 0, 0)),
	)
	testing.expect(
		t,
		matrix_get(m, 0, 1) == 6,
		fmt.tprintf("expected 6: %v, got %v", 6, matrix_get(m, 0, 1)),
	)
	testing.expect(
		t,
		matrix_get(m, 0, 2) == 4,
		fmt.tprintf("expected 4: %v, got %v", 4, matrix_get(m, 0, 2)),
	)
	testing.expect(
		t,
		matrix_get(m, 1, 0) == 2,
		fmt.tprintf("expected 2: %v, got %v", 2, matrix_get(m, 1, 0)),
	)
	testing.expect(
		t,
		matrix_get(m, 1, 1) == 6,
		fmt.tprintf("expected 6: %v, got %v", 6, matrix_get(m, 1, 1)),
	)
	testing.expect(
		t,
		matrix_get(m, 1, 2) == 6,
		fmt.tprintf("expected 6: %v, got %v", 6, matrix_get(m, 1, 2)),
	)
	testing.expect(
		t,
		matrix_get(m, 2, 0) == 5,
		fmt.tprintf("expected 5: %v, got %v", 5, matrix_get(m, 2, 0)),
	)
	testing.expect(
		t,
		matrix_get(m, 2, 1) == 2,
		fmt.tprintf("expected 2: %v, got %v", 2, matrix_get(m, 2, 1)),
	)
	testing.expect(
		t,
		matrix_get(m, 2, 2) == 3,
		fmt.tprintf("expected 3: %v, got %v", 3, matrix_get(m, 2, 2)),
	)
}

@(test)
test_matrix_determinant :: proc(t: ^testing.T) {
	m, err := matrix_init(2, 2, 2)
	defer matrix_deinit(m)
	matrix_set_cauchy(m)
	det: int
	det, err = matrix_determinant(m)
	testing.expect(t, det == 1, fmt.tprintf("expected det: %v, got %v", 5, det))
	m2: Finite_Field_Matrix
	m2, err = matrix_init(3, 3, 3)
	defer matrix_deinit(m2)
	matrix_set_cauchy(m2)
	det, err = matrix_determinant(m2)
	testing.expect(t, det == 7, fmt.tprintf("expected det: %v, got %v", 7, det))
	m3: Finite_Field_Matrix
	m3, err = matrix_init(4, 4, 4)
	defer matrix_deinit(m3)
	matrix_set_cauchy(m3)
	det, err = matrix_determinant(m3)
	testing.expect(t, det == 7, fmt.tprintf("expected det: %v, got %v", 7, det))
}

@(test)
test_matrix_invertible_submatrices :: proc(t: ^testing.T) {
	m, err := matrix_init(5, 3, 3)
	defer matrix_deinit(m)
	matrix_set_cauchy(m)

	num_num_rows_to_exclude := m.num_rows - m.num_cols
	for excluded_num_rows in choose({0, 1, 2, 3, 4}, num_num_rows_to_exclude) {
		fmt.printf("excluding %v...\n", excluded_num_rows)
		submatrix, _ := matrix_submatrix(m, excluded_num_rows[:], {})
		defer matrix_deinit(submatrix)
		testing.expect(t, m.num_cols == submatrix.num_cols)
		inverse, _ := matrix_invert(submatrix)
		defer matrix_deinit(inverse)
		product1, _ := matrix_multiply(inverse, submatrix)
		defer matrix_deinit(product1)
		product2, _ := matrix_multiply(submatrix, inverse)
		defer matrix_deinit(product2)
		for r in 0 ..< product1.num_rows {
			for c in 0 ..< product1.num_cols {
				testing.expect(t, matrix_get(product1, r, c) == matrix_get(product2, r, c), fmt.tprintf(
					"expected same [%d, %d], got %d != %d\n", r, c, matrix_get(product1, r, c), matrix_get(product2, r, c))
				)
				if r == c {
					testing.expect(
						t,
						matrix_get(product1, r, c) == 1,
						fmt.tprintf(
							"expected 0, got matrix[%d, %d]=%d\n",
							r,
							c,
							matrix_get(product1, r, c),
						),
					)
				} else {
					testing.expect(
						t,
						matrix_get(product1, r, c) == 0,
						fmt.tprintf(
							"expected 0, got matrix[%d, %d]=%d\n",
							r,
							c,
							matrix_get(product1, r, c),
						),
					)
				}
			}
		}

	}
}

@(test)
test_matrix_binary_rep :: proc(t: ^testing.T) {
	m, err := matrix_init(5, 3, 3)
	defer matrix_deinit(m)
	matrix_set_cauchy(m)

	for a in 0..<m.field.order {
		mat_a := field_matrix(m.field, a)
		for b in 0..< m.field.order {
			mat_b := field_matrix(m.field, b)
			sum := field_add(m.field, a, b)
			mat_sum := field_matrix(m.field, sum)
			for r in 0..< len(mat_a) {
				for c in 0..< len(mat_a[0]) {
					testing.expect(t, mat_sum[c][r] == field_add(m.field, mat_a[c][r], mat_b[c][r]), fmt.tprintf("expected [%d, %d]: %v, got %v", r, c, mat_sum, field_add(m.field, mat_a[c][r], mat_b[c][r])))
					
				}
			}
		}
	}
}

