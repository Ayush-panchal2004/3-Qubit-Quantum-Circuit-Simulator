#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define NUM_QUBITS 3
#define STATE_SIZE 8
#define MAX_GATES 20

// Complex number struct
typedef struct {
    double real;
    double imag;
} Complex;

// Quantum state
typedef struct {
    Complex amplitudes[STATE_SIZE];
} QState;

// ASCII circuit display
char circuit[NUM_QUBITS][MAX_GATES];

// === Complex number functions ===
Complex c_add(Complex a, Complex b) {
    Complex r = {a.real + b.real, a.imag + b.imag};
    return r;
}

Complex c_mul(Complex a, Complex b) {
    Complex r = {
        a.real * b.real - a.imag * b.imag,
        a.real * b.imag + a.imag * b.real
    };
    return r;
}

double c_abs2(Complex a) {
    return a.real * a.real + a.imag * a.imag;
}

// === Gate matrices ===
#define INV_SQRT2 0.7071067811865476
Complex H[2][2] = {
    {{INV_SQRT2, 0}, {INV_SQRT2, 0}},
    {{INV_SQRT2, 0}, {-INV_SQRT2, 0}}
};

Complex X[2][2] = {
    {{0, 0}, {1, 0}},
    {{1, 0}, {0, 0}}
};

// === Initialize state ===
void init_state(QState *qs) {
    for (int i = 0; i < STATE_SIZE; i++) {
        qs->amplitudes[i].real = 0;
        qs->amplitudes[i].imag = 0;
    }
    qs->amplitudes[0].real = 1; // |000>
}

// === ASCII-safe binary state display ===
void print_state(QState *qs) {
    for (int i = 0; i < STATE_SIZE; i++) {
        printf("|%d%d%d>: %.4f + %.4fi\n",
            (i >> 2) & 1, (i >> 1) & 1, i & 1,
            qs->amplitudes[i].real, qs->amplitudes[i].imag);
    }
}

// === Apply single qubit gate ===
void apply_single_gate(QState *qs, Complex gate[2][2], int target) {
    QState new_state = {0};

    for (int i = 0; i < STATE_SIZE; i++) {
        int bit = (i >> (NUM_QUBITS - 1 - target)) & 1;
        for (int j = 0; j < 2; j++) {
            int flipped = (i & ~(1 << (NUM_QUBITS - 1 - target))) | (j << (NUM_QUBITS - 1 - target));
            new_state.amplitudes[flipped] = c_add(
                new_state.amplitudes[flipped],
                c_mul(gate[j][bit], qs->amplitudes[i])
            );
        }
    }

    *qs = new_state;
}

// === Apply CNOT ===
void apply_cnot(QState *qs, int control, int target) {
    QState new_state = {0};

    for (int i = 0; i < STATE_SIZE; i++) {
        int control_bit = (i >> (NUM_QUBITS - 1 - control)) & 1;
        int new_index = i;

        if (control_bit) {
            new_index ^= (1 << (NUM_QUBITS - 1 - target));
        }

        new_state.amplitudes[new_index] = qs->amplitudes[i];
    }

    *qs = new_state;
}

// === ASCII circuit functions (ASCII-safe) ===
void init_circuit() {
    for (int i = 0; i < NUM_QUBITS; i++)
        for (int j = 0; j < MAX_GATES; j++)
            circuit[i][j] = '-';
}

void add_single_gate_to_circuit(char gate, int qubit, int col) {
    circuit[qubit][col] = gate;
}

void add_cnot_to_circuit(int control, int target, int col) {
    for (int i = 0; i < NUM_QUBITS; i++)
        circuit[i][col] = '|';

    circuit[control][col] = 'O';
    circuit[target][col] = 'X';
}

void print_circuit(int gate_count) {
    printf("\nCircuit:\n");
    for (int i = 0; i < NUM_QUBITS; i++) {
        printf("q%d ", i);
        for (int j = 0; j < gate_count; j++) {
            printf("-%c-", circuit[i][j]);
        }
        printf("\n");
    }
    printf("\n");
}

// === Main ===
int main() {
    QState qs;
    init_state(&qs);
    init_circuit();

    printf("Welcome to Quantum Circuit Simulator!\n");
    printf("\n=== Gate Info ===\n");
    printf("H (Hadamard): Creates superposition. H|0> = (|0> + |1>)/sqrt(2)\n");
    printf("X (Pauli-X): Flips the qubit. X|0> = |1>, X|1> = |0>\n");
    printf("CNOT: If control is 1, flips the target qubit (like classical XOR).\n");

    char proceed[10];
    printf("\nType 'next' to start simulation: ");
    while (1) {
        scanf("%s", proceed);
        if (strcmp(proceed, "next") == 0) break;
        printf("Please type 'next' to begin: ");
    }

    int gate_count = 0;
    char choice[10];

    while (gate_count < MAX_GATES) {
        printf("\n=== Gate #%d ===\n", gate_count + 1);
        printf("Current State:\n");
        print_state(&qs);

        printf("\nEnter gate (H, X, CNOT, DONE): ");
        scanf("%s", choice);

        if (strcmp(choice, "DONE") == 0) break;

        if (strcmp(choice, "H") == 0 || strcmp(choice, "X") == 0) {
            int target;
            printf("Apply %s to which qubit (0-2)? ", choice);
            scanf("%d", &target);

            if (target < 0 || target >= NUM_QUBITS) {
                printf("Invalid qubit.\n");
                continue;
            }

            printf("\n--- Before applying %s on q%d ---\n", choice, target);
            print_state(&qs);

            if (strcmp(choice, "H") == 0)
                apply_single_gate(&qs, H, target);
            else
                apply_single_gate(&qs, X, target);

            printf("\n>>> After applying %s on q%d:\n", choice, target);
            print_state(&qs);

            add_single_gate_to_circuit(choice[0], target, gate_count);
        }

        else if (strcmp(choice, "CNOT") == 0) {
            int control, target;
            printf("Enter control qubit (0-2): ");
            scanf("%d", &control);
            printf("Enter target qubit (0-2): ");
            scanf("%d", &target);

            if (control == target || control < 0 || target < 0 || control >= NUM_QUBITS || target >= NUM_QUBITS) {
                printf("Invalid qubits.\n");
                continue;
            }

            printf("\n--- Before applying CNOT (control q%d, target q%d) ---\n", control, target);
            print_state(&qs);

            apply_cnot(&qs, control, target);

            printf("\n>>> After applying CNOT:\n");
            print_state(&qs);

            add_cnot_to_circuit(control, target, gate_count);
        }

        else {
            printf("Unsupported gate.\n");
            continue;
        }

        gate_count++;
        print_circuit(gate_count);
    }

    printf("\nFinal Quantum State:\n");
    print_state(&qs);
    printf("\nFinal Circuit:\n");
    print_circuit(gate_count);

    return 0;
}
