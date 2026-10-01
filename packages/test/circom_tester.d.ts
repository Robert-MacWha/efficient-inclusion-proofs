declare module "circom_tester" {
  export interface WasmTester {
    calculateWitness(input: object, sanityCheck?: boolean): Promise<bigint[]>;
    checkConstraints(witness: bigint[]): Promise<void>;
  }

  export function wasm(
    circuit: string,
    options?: { include?: string[] },
  ): Promise<WasmTester>;
}
