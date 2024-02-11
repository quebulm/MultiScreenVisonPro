//
//  VirtualDisplayInstance.swift
//  VirtualDisplayMac
//
//  Created by Quentin Ulmer on 10.02.24.
//


import Foundation
import CoreGraphics
import ScreenCaptureKit

class VirtualDisplayInstance {
    var virtualDisplay: CGVirtualDisplay?
    var id: UInt32?
    var width: Int = 0
    var height: Int = 0
    
    init() {}
    
    // Static factory method to create and setup the virtual display asynchronously
    static func createAndIdentifyDisplay(id: UInt16) async -> VirtualDisplayInstance {
        let instance = VirtualDisplayInstance()
        await instance.createDisplayAndIdentify(id: id)
        return instance
    }
    
    private func createDisplayAndIdentify(id: UInt16) async {
        do {
            // Step 1: Fetch available displays before creation
            let initialDisplays = await self.fetchAvailableDisplayIDs()
            
            // Step 2: Create the virtual display
            self.mainInit(id: id)
            
            // Potentially wait a moment for the system to register the new virtual display
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds sleep as an example
            
            // Step 3: Fetch available displays after creation
            let updatedDisplays = await self.fetchAvailableDisplayIDs()
            
            // Find and set the new display ID
            if let newDisplayID = self.findNewDisplayID(initial: initialDisplays, updated: updatedDisplays) {
                self.setId(newDisplayID)
            }
        } catch {
            // Handle errors if any of the awaited calls can throw
            print("An error occurred: \(error)")
        }
    }
    
    private func findNewDisplayID(initial: [UInt32], updated: [UInt32]) -> UInt32? {
        // Convert the initial array to a Set for more efficient lookup
        let initialSet = Set(initial)
        
        // Iterate through the updated array
        for id in updated {
            // Check if the id from the updated array is not in the initial set
            if !initialSet.contains(id) {
                // If the id is new (not contained in the initial set), return it
                return id
            }
        }
        
        // If no new id is found, return nil
        return nil
    }

    
    private func mainInit(id: UInt16) {
        self.id = UInt32(id)

        // Initialize virtual display descriptor
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.name = "My Virtual Display \(id)"
        descriptor.maxPixelsWide = 1920
        descriptor.maxPixelsHigh = 1080
        self.height = 1080
        self.width = 1920
        descriptor.sizeInMillimeters = CGSize(width: 1920, height: 1080)

        // Machen Sie `vendorID`, `productID`, `serialNum` einzigartig basierend auf der `id`
        descriptor.vendorID = 0x1234 + UInt32(id)
        descriptor.productID = 0x5678 + UInt32(id)
        // Der SerialNum könnte einfach als `id` selbst benutzt werden, falls eine echte Einzigartigkeit gewünscht ist
        descriptor.serialNum = UInt32(id)
        
        // Verwende die id, um die Queue eindeutig zu kennzeichnen
        descriptor.queue = DispatchQueue(label: "com.example.virtualdisplay.\(id)")

        // Initialize display settings
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 2
        let mode = CGVirtualDisplayMode(width: 1920, height: 1080, refreshRate: 60.0)
        settings.modes = [mode]

        // Create the virtual display
        self.virtualDisplay = CGVirtualDisplay(descriptor: descriptor)
        let success = self.virtualDisplay?.apply(settings) ?? false

        if success {
            print("Virtual display \(id) successfully created.")
        } else {
            print("Failed to create virtual display \(id).")
        }
    }
    
    // Placeholder methods for fetching display IDs and finding the new display ID
    private func fetchAvailableDisplayIDs() async -> [UInt32] {
        var availableDisplayList: [UInt32] = [] // Correctly declare an array to store Int32 values

        do {
            // Retrieve the available content to capture
            let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            
            // Loop through the displays and add their displayID to the list
            for display in availableContent.displays {
                availableDisplayList.append(display.displayID)
            }
            
            return availableDisplayList // Return the populated list of display IDs
        } catch {
            // Handle errors if any of the awaited calls can throw
            print("An error occurred while fetching available display IDs: \(error)")
            return [] // Return an empty array if there's an error
        }
    }
    
    private func setId(_ id: UInt32) {
        self.id = id
        print("Updated virtual display ID to \(id).")
    }
}

