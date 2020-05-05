//
//  ViewController.swift
//  ARrehab
//
//  Created by Eric Wang on 2/12/20.
//  Copyright © 2020 Eric Wang. All rights reserved.
//

import UIKit
import RealityKit
import ARKit
import Combine

class ViewController: UIViewController {
    
    /// AR View
    @IBOutlet var arView: ARView!
    
    var visualizedPlanes : [ARPlaneAnchor] = []
    var activeButtons : [UIButton] = []
    var trackedRaycasts : [ARTrackedRaycast?] = []
    
    var boardState : BoardState = .notMapped
    
    
    var tileGrid: TileGrid?
    var gameBoard: GameBoard?
    
    /// The Player Entity that is attached to the camera.
    let playerEntity = Player(target: .camera)

    /// The ground anchor entity that holds the tiles and other fixed game objects
//  var groundAncEntity: AnchorEntity!

    /// Switch that turns on and off the Minigames, cycling through them.
    @IBOutlet var minigameSwitch: UISwitch!
    /// Label to display minigame output.
    @IBOutlet var minigameLabel: UILabel!
  
    /// Minigame Controller Struct
    var minigameController: MinigameController!
    var subscribers: [Cancellable] = []
    
    /// Add the player entity and set the AR session to begin detecting the floor.
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        //Assign the ViewController class to act as the session's delegate (extension below)
        arView.session.delegate = self
        startTracking()
        
        //Set up the player entity
        //arView.scene.addAnchor(playerEntity)
        //playerEntity.addCollision()
        
        //Setup the Minigame. Switch is used for debugging purposes. In the product it should be a seamless transition.
//         minigameSwitch.setOn(false, animated: false)
//         //groundAncEntity is the ground ARAnchorEntity of the board.
//         minigameController = MinigameController(ground: groundAncEntity.copy(recursive: false), player: playerEntity)
//         scoreSubscriber = minigameController.$score.sink(receiveValue: { (score) in
//             self.minigameLabel.text = String(format:"Score: %0.0f", score)
//         })
//         minigameSwitch.addTarget(self, action: #selector(minigameSwitchStateChanged), for: .valueChanged)
        
//        self.arView.scene.addAnchor(groundAncEntity)
//        minigameController = MinigameController(ground: groundAncEntity, player: cameraEntity)
//        subscribers.append(minigameController.$score.sink(receiveValue: { (score) in
//            self.minigameLabel.text = String(format:"Score: %0.0f", score)
//        }))
//        minigameSwitch.addTarget(self, action: #selector(minigameSwitchStateChanged), for: .valueChanged)
    }
    
    private func startTracking() {
        //Define AR Configuration to detect horizontal surfaces
        let arConfig = ARWorldTrackingConfiguration()
        arConfig.planeDetection = .horizontal
        
        //Check if the device supports depth-based people occlusion and activate it if so
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            arConfig.frameSemantics.insert(.personSegmentationWithDepth)
        } else {
            print("This device does not support people occlusion")
        }
        
        //Run the tracking configuration (start detecting planes)
        self.arView.session.run(arConfig)
    }
    
}

//Extension of ViewController that acts as a delegate for the AR session
//Recieves updated scene info, can initiate actions based on scene-related events (i.e. anchor detection
extension ViewController: ARSessionDelegate {
        
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        if self.boardState == .notMapped {
            if let validPlaneAnc = checkForValid(anchors: anchors) {
                self.initiateBoardLayout(surfaceAnchor: validPlaneAnc)
            }
        }
            
        else if self.boardState == .mapped {
            if let updatedAnchor = checkForUpdate(anchors: anchors) {
                self.tileGrid?.updateBoard(updatedAnc: updatedAnchor)
            }
        }        
    }
    
    //Checks a list of anchors for one that meets the valid surface requirements described by the GameBoard's EXTENT constants
    func checkForValid(anchors: [ARAnchor]) -> ARPlaneAnchor? {
        guard self.boardState == .notMapped else {return nil}
        for anc in anchors {
            if let planeAnc = anc as? ARPlaneAnchor {
                if isValidSurface(plane: planeAnc) {
                    return planeAnc
                }
            }
        }
        return nil
    }
    
    //Checks a list of anchors for one that matches the surface anchor of the tileGrid's surfaceAnchor
    func checkForUpdate(anchors: [ARAnchor]) -> ARPlaneAnchor? {
        guard self.boardState == .mapped else {return nil}
        for anc in anchors {
            if let planeAnc = anc as? ARPlaneAnchor {
                if planeAnc == self.tileGrid?.surfaceAnchor {
                    return planeAnc
                }
            }
        }
        return nil
    }
    
    func initiateBoardLayout(surfaceAnchor: ARPlaneAnchor) {
        guard self.boardState == .notMapped else {return}
        self.boardState = .mapping
        
        self.tileGrid = TileGrid(surfaceAnchor: surfaceAnchor)
        self.arView.scene.addAnchor(self.tileGrid!.gridEntity)
        self.boardState = .mapped
        
        self.addPbButton()
        self.addRbButton()
        self.startBoardPlacement()
    }
    
    func startBoardPlacement() {
        
        self.arView.scene.addAnchor(playerEntity)
        self.playerEntity.addCollision()
        
        Timer.scheduledTimer(withTimeInterval: TimeInterval(exactly: 1.0)!, repeats: true) {timer in
            
            if self.boardState == .placed {
                timer.invalidate()
            }
                
            else if (self.playerEntity.onTile != nil) {
                self.tileGrid?.updateBoardOutline(centerTile: self.playerEntity.onTile!)
            }
            
        }
    }
    
}

/*
 Helper functions
 */
extension ViewController {
    
    
    //Enumerator to represent current state of the game board
    enum BoardState {
        case notMapped
        case mapping
        case mapped
        case placed
    }
    
    //Checks if plane is valid surface, according to x and z extent
    func isValidSurface(plane: ARPlaneAnchor) -> Bool {
        guard plane.alignment == .horizontal else {return false}
        
        let minBoundary = min(plane.extent.x, plane.extent.z)
        let maxBoundary = max(plane.extent.x, plane.extent.z)
        
        let minExtent = min(GameBoard.EXTENT1, GameBoard.EXTENT2)
        let maxExtent = max(GameBoard.EXTENT1, GameBoard.EXTENT2)
        
        return minBoundary >= minExtent && maxBoundary >= maxExtent
    }
    
    
    //Plane visualization methods, for use in development
    func visualizePlanes(anchors: [ARAnchor]) {
        
        let pointModel = ModelEntity.init(mesh: MeshResource.generateSphere(radius: 0.01))
        
        for anc in anchors {
            
            guard let planeAnchor = anc as? ARPlaneAnchor else {return}
            let planeAnchorEntity = AnchorEntity(anchor: planeAnchor)
                        
            for point in planeAnchor.geometry.boundaryVertices {
                let pointEntity = pointModel
                pointEntity.transform.translation = point
                planeAnchorEntity.addChild(pointEntity)
            }
            
            let planeModel = ModelEntity()
            planeModel.model = ModelComponent(mesh: MeshResource.generatePlane(width: planeAnchor.extent.x, depth: planeAnchor.extent.z), materials: [SimpleMaterial(color: SimpleMaterial.Color.blue, isMetallic: false)])
            planeModel.transform.translation = planeAnchor.center
            planeAnchorEntity.addChild(planeModel)
            
            let center = ModelEntity(mesh: MeshResource.generateBox(width: 0.1, height: 1, depth: 0.1), materials: [SimpleMaterial.init()])
            center.transform.translation = planeAnchor.center
            planeAnchorEntity.addChild(center)
            
            planeAnchorEntity.name = planeAnchor.identifier.uuidString
            
            arView.scene.addAnchor(planeAnchorEntity)
            self.visualizedPlanes.append(planeAnchor)
        }
        
    }
    
    func visualizePlanes(anchors: [ARAnchor], floor: Bool) {
        let validAnchors = anchors.filter() {anc in
            guard let planeAnchor = anc as? ARPlaneAnchor else {return false}
            return isValidSurface(plane: planeAnchor) == floor
        }
        visualizePlanes(anchors: validAnchors)
    }
    
    func updatePlaneVisual(anchors: [ARAnchor]) {
        for anc in anchors {
            
            guard let planeAnchor = anc as? ARPlaneAnchor else {return}
            
            guard let planeAnchorEntity = self.arView.scene.findEntity(named: planeAnchor.identifier.uuidString) else {return}
            
            var newBoundaries = [ModelEntity]()
            
            for point in planeAnchor.geometry.boundaryVertices {
                let pointEntity = ModelEntity.init(mesh: MeshResource.generatePlane(width: 0.01, depth: 0.01))
                pointEntity.transform.translation = point
                newBoundaries.append(pointEntity)
            }
            
            planeAnchorEntity.children.replaceAll(newBoundaries)
            
            let modelEntity = ModelEntity(mesh: MeshResource.generatePlane(width: planeAnchor.extent.x, depth: planeAnchor.extent.z), materials: [SimpleMaterial(color: SimpleMaterial.Color.blue, isMetallic: false)])
            modelEntity.transform.translation = planeAnchor.center
            
            planeAnchorEntity.addChild(modelEntity)
        }
    }
}

/**
 Minigame Helper Functions
 */
extension ViewController {
    /**
     Minigame switch logic.
     Switched on: a new game is created.
     Switched off: score is displayed and game is removed.
     */
    @objc func minigameSwitchStateChanged(switchState: UISwitch) {
        if switchState.isOn {
            let controller = minigameController.enableMinigame()
            addController(controller: controller)
        } else {
            minigameController.disableMinigame()
        }
    }
    
    /**
     Adds the controller as a subview programmatically.
     */
    private func addController(controller: UIViewController) {
        // Add the View Controller as a subview programmatically.
        addChild(controller)
        // TODO Make a better frame depending on what UI elements are going to persist such that the Minigame Controller will not confict with the Persistent UI.
        var frame = self.view.frame.insetBy(dx: 0, dy: 100)
        controller.view.frame = frame
        self.view.addSubview(controller.view)
        controller.didMove(toParent: self)
    }
}
