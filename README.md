# Quantum Circuit Simulator in C 🧠

This project is a **3-qubit quantum circuit simulator** written in C. It simulates basic quantum gates and visualizes the quantum circuit using ASCII art in the terminal. It’s designed to help beginners understand how gates like **Hadamard (H)**, **Pauli-X (X)**, and **CNOT** affect the quantum state vector.

All operations are done using complex numbers, implemented manually without any external libraries. The quantum state updates in real time after each gate is applied, and the result is displayed in both amplitude and circuit form.

---

## ✨ Features

- Simulates 3-qubit quantum circuits
- Supports `H`, `X`, and `CNOT` gates
- Interactive terminal-based gate input
- Shows quantum state amplitudes (real + imaginary)
- ASCII circuit diagram updates after each gate

---

## 🛠️ How to Compile & Run

```bash
gcc main.c -o simulator -lm
./simulator
