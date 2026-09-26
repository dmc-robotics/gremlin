import SwiftUI

/// How to format data sent from an Arduino sketch.
struct SerialProtocolHelp: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Serial Data Protocol")
                        .font(.title3.weight(.semibold))
                    Text("How to format data sent from your Arduino over serial.")
                        .foregroundStyle(.secondary)
                }

                section(
                    "Key/Value Pairs",
                    "Send named values separated by a colon. Multiple pairs can be sent on one line, separated by commas.",
                    code: "temperature:23.4\nrpm:1200,voltage:4.97"
                )
                section(
                    "Log Levels",
                    "Prefix a line with ERROR:, WARN:, INFO:, or DEBUG: to color it in the monitor.",
                    code: "WARN:battery low\nERROR:sensor not found"
                )
                section(
                    "Plain Text",
                    "Any other line is shown as-is in the monitor.",
                    code: "Setup complete.\nLoop started."
                )
                section(
                    "Plotter Values",
                    "Key/value pairs are graphed in the Plotter. Use consistent key names across lines to build traces.",
                    code: "x:0.00,y:1.00\nx:0.10,y:0.99\nx:0.20,y:0.98"
                )
                section(
                    "Arduino Example",
                    "Send key/value pairs from your sketch with Serial.print():",
                    code: """
                        void setup() {
                          Serial.begin(9600);
                          Serial.println("Setup complete.");
                        }

                        void loop() {
                          float temp = readTemperature();
                          int rpm  = readRPM();

                          Serial.print("temperature:");
                          Serial.print(temp);
                          Serial.print(",rpm:");
                          Serial.println(rpm);   // println ends the line

                          delay(100);
                        }
                        """
                )
                section(
                    "Raw Mode",
                    "Turn on Raw to see lines exactly as received, without timestamps or colors.",
                    code: nil
                )
            }
            .padding(20)
        }
        .frame(width: 440, height: 520)
    }

    private func section(_ title: String, _ text: String, code: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let code {
                Text(code)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 6))
            }
        }
    }
}
