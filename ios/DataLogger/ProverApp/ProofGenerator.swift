import Foundation
import JavaScriptCore

/// Wraps snarkjs.groth16.fullProve in JSCore.
class ProofGenerator {
    static let shared = ProofGenerator()
    private let context: JSContext

    private init() {
        context = JSContext()!

        // 1) Load snarkjs.min.js
        let jsURL  = Bundle.main.url(forResource: "snarkjs.min", withExtension: "js")!
        let jsCode = try! String(contentsOf: jsURL, encoding: .utf8)
        context.evaluateScript(jsCode)

        // 2) Polyfill Buffer & atob/btoa
        let polyfills =
        """
        const Buffer = { from: arr => new Uint8Array(arr) };
        if (typeof atob === 'undefined') {
          global.atob = s => Buffer.from(atob(s));
        }
        if (typeof btoa === 'undefined') {
          global.btoa = bin => '';
        }
        """
        context.evaluateScript(polyfills)

        // 3) Inject our fullProve() wrapper
        let wrapper =
        """
        async function fullProve(nonceArray, wasmBytes, zkeyBytes) {
          const input = { nonce: nonceArray };
          const { proof, publicSignals } =
            await snarkjs.groth16.fullProve(input, wasmBytes, zkeyBytes);
          return { proof, publicSignals };
        }
        """
        context.evaluateScript(wrapper)
    }

    /// Generate a Groth16 proof for the given 8-byte nonce.
    func fullProve(
        nonce: Data,
        completion: @escaping (_ proof: [String:Any]?,
                               _ publicSignals: [Any]?,
                               _ error: Error?) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // 4) Load & decode the .wasm and .zkey from bundle
                let wasmURL = Bundle.main.url(forResource: "proximity", withExtension: "wasm")!
                let zkeyURL = Bundle.main.url(forResource: "proximity_final", withExtension: "zkey")!
                let wasmData = try Data(contentsOf: wasmURL)
                let zkeyData = try Data(contentsOf: zkeyURL)

                // 5) Prepare JS arrays by wrapping Swift arrays as JS arrays
                let nonceInts    = nonce.map { Int($0) }
                let wasmInts     = [UInt8](wasmData).map { Int($0) }
                let zkeyInts     = [UInt8](zkeyData).map { Int($0) }

                guard
                  let nonceJS   = JSValue(object: nonceInts,   in: self.context),
                  let wasmJS    = JSValue(object: wasmInts,    in: self.context),
                  let zkeyJS    = JSValue(object: zkeyInts,    in: self.context),
                  let fpFunc    = self.context.objectForKeyedSubscript("fullProve")
                else {
                    throw NSError(
                      domain: "ProofGenerator",
                      code: 2,
                      userInfo: [NSLocalizedDescriptionKey:
                        "Failed to prepare JS arguments"]
                    )
                }

                // 6) Call fullProve(nonceJS, wasmJS, zkeyJS)
                guard let promise = fpFunc.call(
                    withArguments: [nonceJS, wasmJS, zkeyJS]
                ) else {
                    throw NSError(
                      domain: "ProofGenerator",
                      code: 3,
                      userInfo: [NSLocalizedDescriptionKey:
                        "fullProve() returned nil"]
                    )
                }

                // 7) Attach success & error callbacks
                _ = promise.invokeMethod("then", withArguments: [
                    { (res: JSValue) in
                        let proof = res.forProperty("proof")?.toDictionary()
                                   as? [String:Any]
                        let signals = res.forProperty("publicSignals")?.toArray()
                        DispatchQueue.main.async {
                            completion(proof, signals, nil)
                        }
                    },
                    { (err: JSValue) in
                        DispatchQueue.main.async {
                            completion(nil, nil, NSError(
                                domain: "ProofGenerator",
                                code: 4,
                                userInfo: [NSLocalizedDescriptionKey:
                                  err.toString() ?? "JS error"]
                            ))
                        }
                    }
                ])
            } catch {
                DispatchQueue.main.async {
                    completion(nil, nil, error)
                }
            }
        }
    }
}
