
import Foundation
import PencilKit

// macOS supports PencilKit since 10.15, so we can run this as a script
// provided we import the right framework and run it in the right context.
// 'swift' command might struggle with frameworks if not built properly.
// Let's try a simple approach first: 

// 1. Create a dummy base64 string that represents a ~5KB drawing
// (We know from experience a simple signature is ~2-5KB)
let estimatedSimpleDrawingSize = 5 * 1024 
let estimatedComplexDrawingSize = 500 * 1024 // 500KB

print("--- Estimated Sizes ---")
print("Simple Drawing (Binary): \(estimatedSimpleDrawingSize) bytes")
print("Complex Drawing (Binary): \(estimatedComplexDrawingSize) bytes")

// Base64 adds ~33% overhead
let simpleBase64 = Int(Double(estimatedSimpleDrawingSize) * 1.33)
let complexBase64 = Int(Double(estimatedComplexDrawingSize) * 1.33)

print("Simple Drawing (Base64): \(simpleBase64) chars")
print("Complex Drawing (Base64): \(complexBase64) chars")

print("\n--- Notion Limits ---")
print("Text Property Limit: 2,000 characters")
print("Rich Text Property Limit: 2,000 chars per text object (block limit is higher)")

print("\n--- Feasibility Check ---")
if simpleBase64 > 2000 {
    print("❌ Simple drawings WILL NOT fit in a standard Text property (limit 2000)")
} else {
    print("✅ Simple drawings might fit")
}

// Check if we can split rich text
// Notion blocks (like paragraphs) have a limit of ~2000 chars per text object, 
// but a paragraph block can contain multiple rich text objects.
// However, a DATABASE PROPERTY (Rich Text) also has limits.
// Historically, the total limit for a Rich Text property is around 2000 chars.
