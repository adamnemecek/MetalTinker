//
//  Copyright © 1887 Sherlock Holmes. All rights reserved.
//  Found amongst his effects by r0ml
//

import Foundation
import AppKit
import MetalKit
import os
// import AVFoundation
// import SwiftUI


/** This class processes the initializer and sets up the shader parameters based on the shader defaults and user defaults */

public class ConfigController {

  var initializationBuffer : MTLBuffer!

  // this is the clear color for alpha blending?
  var clearColor : SIMD4<Float> = SIMD4<Float>( 0.16, 0.17, 0.19, 1 )


  private var cached : [IdentifiableView]?
  private var kbuff : MyMTLStruct!
  private var renderManager : RenderManager

  var textureNames : [String] {
    get {
      configQ.sync(flags: .barrier) {
        return _textureNames.map { $0 }
      }
    }
  }
  var cubeNames : [String] {
    get {
      configQ.sync(flags: .barrier) {
        return _cubeNames.map { $0 }
      }
    }
  }
  
  var videoNames : [VideoSupport] {
    get {
      configQ.sync(flags: .barrier) {
        return _videoNames.map { $0 }
      }
    }
  }
  
  var musicNames : [SoundSupport] {
    get {
      configQ.sync(flags: .barrier) {
        return _musicNames.map { $0 }
      }
    }
  }
  
  private var _textureNames : [String] = []
  private var _cubeNames : [String] = []
  private var _videoNames : [VideoSupport] = []
  private var _musicNames : [SoundSupport] = []
  
  var pipelinePasses : [PipelinePass] = []
  
  // var microphone : Int? -- this got folded into musicNames
  var webcam : WebcamSupport?
  
  private var myOptions : MyMTLStruct!
  private var dynPref : DynamicPreferences? // need to hold on to this for the callback
  
  private var shaderName : String
  
  private var configQ = DispatchQueue(label: "config q")

  private var computeBuffer : MTLBuffer?

  private var empty : CGImage

  /** This sets up the initializer by finding the function in the shader,
   using reflection to analyze the types of the argument
   then setting up the buffer which will be the "preferences" buffer.
   It would be the "Uniform" buffer, but that one is fixed, whereas this one is variable -- so it's
   just easier to make it a separate buffer
   */


  init(_ x : String, _ rm : RenderManager) {
    shaderName = x
    renderManager = rm
    empty = NSImage(named: "BrokenImage")!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
//    textureThumbnail = Array(repeating: nil, count: numberOfTextures)
    inputTexture = Array(repeating: nil, count: RenderManager.numberOfTextures)
  }
  
  // this is getting called during onTapGesture in LibraryView -- when I'm launching the ShaderView
  func buildPrefView() -> [IdentifiableView] {
    if let z = cached { return z }
    if let mo = myOptions {
      let a = DynamicPreferences.init(shaderName, self)
      dynPref = a
      cached = a.buildOptionsPane(mo)
      return cached!
      // dynPref = a
      
    }
    return []
  }
  
  func getClearColor(_ bst : MyMTLStruct) {
    if let v : SIMD4<Float> = bst["clearColor"]?.getValue() {
      self.clearColor = v
    }
  }
  
  func processMicrophone(_ bst : MyMTLStruct ) {
    if let _ = bst["microphone"] {
      _musicNames.append( MicrophoneSupport() )
    }
  }
  
  func processWebcam(_ bst : MyMTLStruct ) {
    if let _ = bst["webcam"] {
      webcam = WebcamSupport()
    }
  }

  func purge() {
    _videoNames.forEach {
      $0.endProcessing()
    }
    _musicNames.forEach {
      $0.stopStreaming()
    }
    
    _videoNames = []
    _musicNames = []
  }

  func processOptions(_ bst : MyMTLStruct ) {
    guard let mo = bst["options"] else {
      return
    }
    myOptions = mo
    
    for bstm in myOptions.children {
      let dnam = "\(self.shaderName).\(bstm.name!)"
      // if this key already has a value, ignore the initialization value
      let dd =  UserDefaults.standard.object(forKey: dnam)
      
      if let _ = bstm.structure {
        let ddm = bstm.children
        self.segmented(bstm.name, ddm)
        // self.dropDown(bstm.name, ddm) } }
        
      } else {
        
        let dat = bstm.value
        switch dat {
        case is Bool:
          let v = dat as! Bool
          UserDefaults.standard.set(dd ?? v, forKey: dnam)
          self.boolean(bstm);
          
        case is SIMD4<Float>:
          let v = dat as! SIMD4<Float>
          UserDefaults.standard.set(dd ?? v.y, forKey: dnam)
          self.colorPicker( bstm)
          
        case is SIMD3<Float>:
          let v = dat as! SIMD3<Float>
          UserDefaults.standard.set(dd ?? v.y, forKey: dnam)
          self.numberSliderFloat( bstm )
          
        case is SIMD3<Int32>:
          let v = dat as! SIMD3<Int32>
          UserDefaults.standard.set(dd ?? v.y, forKey: dnam)
          self.numberSliderInt( bstm )
          
        default:
          os_log("%s", type:.error, "\(bstm.name!) is \(bstm.datatype)")
        }
      }
    }
  }
  
  func processVideos(_  bst: MyMTLStruct ) {
    _videoNames = []
    if let bss = bst.getStructArray("videos") {
      for bb in bss {
        if let jj = bb.getString(),
          let ii = Bundle.main.url(forResource: jj, withExtension: nil, subdirectory: "videos") {
          // print("appending \(jj) for \(self.shaderName ?? "" )")
          _videoNames.append( VideoSupport( ii ) )
        }
      }
    }
  }
  
  func processMusic(_  bst: MyMTLStruct ) {
    _musicNames = []
    if let bss = bst.getStructArray("music") {
      for bb in bss {
        if let jj = bb.getString() {
          // if jj == "microphone" {
          //   musicNames.append( MicrophoneSupport() )
          // } else
          if let ii = Bundle.main.url(forResource: jj, withExtension: nil, subdirectory: "music") {
            // print("appending \(jj) for \(self.shaderName ?? "" )")
            _musicNames.append( SoundSupport( ii ) )
          } else {
            os_log("failed to load music %s", type:.info, jj)
          }
        }
      }
    }
  }

  private var textureLoader = MTKTextureLoader(device: device)
  var inputTexture : [MTLTexture?]

  func processTextures(_ bst : MyMTLStruct ) {
    _textureNames = []
    if let bss = bst.getStructArray("textures") {
      for bb in bss {
        if let jj = bb.getString() {
          _textureNames.append(jj)
        }
      }
    }

    // this is loading textures.....
    let z : [String] = textureNames
    for (txtd, url) in z.enumerated() {
      do {
        let p = try self.textureLoader.newTexture(name: url, scaleFactor: 1.0, bundle: Bundle.main, options: [MTKTextureLoader.Option.textureStorageMode : MTLStorageMode.private.rawValue] )
      //  p.setPurgeableState(.volatile)
        self.inputTexture[txtd] = p
        DispatchQueue.main.async {
          self.renderManager.textureThumbnail[txtd] = p.cgImage  ?? self.empty
        }
      } catch(let e) {
        let m = "failed to load texture \(url) in \(shaderName): \(e.localizedDescription)"
        os_log("*** %s ***", type: .error, m)
      }
    }
  }

 /* func getTextureThumbnail(_ n : Int) -> CGImage {
    if let t = textureThumbnail[n] {
      return t
    } else {
      if let it = inputTexture[n],
        let ti = CIImage.init(mtlTexture: it, options: nil),
        let tt = ti.cgImage { // CIContext(options: nil).createCGImage(ti, from: ti.extent) {
        textureThumbnail[n] = tt
        return tt
      } else {
        textureThumbnail[n] = empty
        return empty
      }
    }
  } */

  func processCubes(_ bst : MyMTLStruct ) {
    _cubeNames = []
    if let bss = bst.getStructArray("cubes") {
      for bb in bss {
        if let jj = bb.getString() {
          _cubeNames.append(jj)
        }
      }
    }
  }
  
  func segmented( _ t:String, _ items : [MyMTLStruct]) {
    let iv = UserDefaults.standard.integer(forKey: "\(self.shaderName).\(t)")
    setPickS(iv, items)
    // sb.selectedSegment = iv
  }
  
  // FIXME: this is a duplicate of the one in DynamicPreferences
  func setPickS(_ a : Int, _ items : [MyMTLStruct] ) {
    for (i, tt) in items.enumerated() {
      tt.setValue(i == a ? 1 : 0 )
    }
  }
  
  func boolean(_ arg : MyMTLStruct) {
    arg.setValue( UserDefaults.standard.bool(forKey: "\(self.shaderName).\(arg.name!)") )
  }
  
  func colorPicker(_ arg : MyMTLStruct) {
    if let iv = UserDefaults.standard.color(forKey: "\(self.shaderName).\(arg.name!)") {
      arg.setValue(iv.asFloat4())
    }
  }
  
  func numberSliderInt(_ arg : MyMTLStruct) {
    let iv = UserDefaults.standard.integer(forKey: "\(self.shaderName).\(arg.name!)")
    // note the ".y"
    if var z : SIMD3<Int32> = arg.value as? SIMD3<Int32> {
      z.y = Int32(iv)
      arg.setValue(z)
    }
    //    (getBufPtr(n) as UnsafeMutablePointer<SIMD3<Int32>>).pointee.y = Int32(iv)
  }
  
  func numberSliderFloat(_ arg : MyMTLStruct) {
    let iv = UserDefaults.standard.float(forKey: "\(self.shaderName).\(arg.name!)")
    // note the ".y"
    if var z : SIMD3<Float> = arg.value as? SIMD3<Float> {
      z.y = iv
      arg.setValue(z)
    }
    //    (getBufPtr(n) as UnsafeMutablePointer<SIMD3<Float>>).pointee.y = iv
  }

  /** this calls the GPU initialization routine to get the initial default values
   Take the contents of the buffer and save them as UserDefaults
   If the UserDefaults were previously set, ignore the results of the GPU initialization.

   This should only be called once at the beginning of the render -- when the view is loaded
   */
  func doInitialization( _ live : Bool, config : ConfigController, size canvasSize : CGSize ) -> MTLBuffer? {

    let nam = shaderName + "InitializeOptions"
    // pipeline state for running a kernel shader "initializer"
    guard let initializationProgram = findFunction( nam ) else {
      print("no initialization program for \(self.shaderName)")
      return nil
    }
    let cpld = MTLComputePipelineDescriptor()
    cpld.computeFunction = initializationProgram

    let commandBuffer = commandQueue.makeCommandBuffer()!
    commandBuffer.label = "Initialize command buffer for \(self.shaderName) "

    let uniformSize : Int = MemoryLayout<Uniform>.stride
    let uni = device.makeBuffer(length: uniformSize, options: [.storageModeManaged])!
    uni.label = "uniform"

    //    if(device.argumentBuffersSupport != MTLArgumentBuffersTier.tier2) {
    //      assert(true, "This sample requires a Metal device that supports Tier 2 argument buffers.");
    //    }

    var cpr : MTLComputePipelineReflection?
    do {
      let initializePipelineState = try device.makeComputePipelineState(function: initializationProgram,
                                                                        options:[.argumentInfo, .bufferTypeInfo], reflection: &cpr)

      if let gg = cpr?.arguments.first(where: { $0.name == "kbuff" }),
        let ib = device.makeBuffer(length: gg.bufferDataSize, options: [.storageModeShared ]) {
        ib.label = "defaults buffer for \(self.shaderName)"
        ib.contents().storeBytes(of: 0, as: Int.self)
        initializationBuffer = ib
      } else if let ib = device.makeBuffer(length: 8, options: [.storageModeShared]) {
        ib.label = "empty kernel compute buffer for \(self.shaderName)"
        initializationBuffer = ib
      } else {
        os_log("failed to allocation initialization MTLBuffer", type: .fault)
        return uni
      }

      //      guard let initializePipelineState = self.initializePipelineState else {
      //        return uni
      //      }

      if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
        computeEncoder.label = "initialization and defaults encoder \(self.shaderName)"
        computeEncoder.setComputePipelineState(initializePipelineState)
        computeEncoder.setBuffer(uni, offset: 0, index: uniformId)
        computeEncoder.setBuffer(initializationBuffer, offset: 0, index: kbuffId)
        let ms = MTLSize(width: 1, height: 1, depth: 1);
        computeEncoder.dispatchThreadgroups(ms, threadsPerThreadgroup: ms);
        //      computeEncoder.dispatchThreads(MTLSize(width: 1, height: 1,depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1,depth: 1))
        computeEncoder.endEncoding()
      }
      commandBuffer.commit()
      commandBuffer.waitUntilCompleted() // I need these values to proceed

    } catch {
      os_log("%s", type:.fault, "failed to initialize pipeline state for \(shaderName): \(error)")
      return nil
    }


    // at this point, the initialization (preferences) buffer has been set
    if let gg = cpr?.arguments.first(where: { $0.name == "kbuff" }) {
      kbuff = MyMTLStruct.init(initializationBuffer, gg)
      processTextures(kbuff)
      processVideos(kbuff)
      processMicrophone(kbuff)
      processWebcam(kbuff)
      processMusic(kbuff)
      processCubes(kbuff)
      processOptions(kbuff)
      getClearColor(kbuff)
      //      setupPipelines(size: canvasSize )
    }
    return uni
  }

  func resetTarget() {
    pipelinePasses = []
  }

  /*  func setupNewTarget(_ canvasSize : CGSize) {
   if let kbuff = kbuff {
   setupPipelines(size: canvasSize)
   }
   } */

  
  func setupPipelines(size canvasSize : CGSize) {
    pipelinePasses = []
    var lastRender : MTLTexture?
    if let f = findFunction("\(shaderName)______Kernel"),
      let p = ComputePipelinePass(
        label: "frame initialize compute in \(shaderName)",
        gridSize: (1, 1 ) ,
        flags: Int32(0),
        function: f) {
      self.computeBuffer = p.computeBuffer
      pipelinePasses.append(p)
    }

    if let j = kbuff["pipeline"] {
      let jc = j.children
      for  (xx, mm) in jc.enumerated() {
        let sfx = mm

        // HERE is where I can also figure out blend mode and clear mode (from the fourth int32)

        // a bool datatype is a filter pass
        if  mm.datatype == .int {
          // presuming that this is a pipeline which involves calling a different (named) shader.

          // it cannot be a generalized shader.  It needs to be a fragment shader which takes a texture in and produces a texture out
          if let f = findFunction("\(mm.name!)___Filter"),
            let l = lastRender ?? inputTexture[0],
            let p = FilterPipelinePass(
              label: "\(sfx.name!) in \(shaderName)",
              size: canvasSize,
              flags: 0,
              function:f,
              input: l,
              isFinal: xx == jc.count - 1) {
            pipelinePasses.append(p)
            lastRender = p.texture // output from the filter pass
          } else {
            os_log("failed to create filter pipeline pass for %s", type: .error, String("\(sfx.name!) in \(shaderName)"))
          }
          // an int datatype is a blit pass -- it will blit copy n textures
          // in order to do so, it will create n pairs of textures, which will be set up
          // as render pass inputs for the next render pass
          //        } else if mm.datatype == .int {
          //          let pms : Int32 = mm.getValue()

        } else {

          // the compute pipeline
          let pms : SIMD4<Int32> = mm.getValue()
          if (pms[0] == -1 ) {
            if let f = findFunction("\(shaderName)___\(sfx.name!)___Kernel"),
              let p = ComputePipelinePass(
                label: "\(sfx.name!) in \(shaderName)",
                gridSize: (Int(pms[1]), Int(pms[2])) ,
                flags: pms[3],
                function: f) {
              self.computeBuffer = p.computeBuffer
              pipelinePasses.append(p)
            }
          } else {
            if let vertexProgram = currentVertexFn(sfx.name) ?? findFunction("flatVertexFn"),
              let fragmentProgram = currentFragmentFn(sfx.name) ?? findFunction("passthruFragmentFn"),
              let ptc = MTLPrimitiveType.init(rawValue: UInt(pms[0])),
              let p = RenderPipelinePass(
                label: "\(sfx.name!) in \(shaderName)",
                viCount: (Int(pms[1]), Int(pms[2])),
                flags: pms[3],
                canvasSize: canvasSize,
                topology: ptc,
                computeBuffer : self.computeBuffer,
                functions: (vertexProgram, fragmentProgram),
                isFinal: xx == jc.count - 1) {

              // At this juncture, I must insert the blitter
              /*    let bce = commandBuffer.makeBlitCommandEncoder()!
               for i in 0..<numberOfRenderPasses {
               if let a = renderPassOutputs[i],
               let b = renderPassInputs[i] {
               bce.copy(from: a, to: b)
               }
               }
               bce.endEncoding()
               */


              //              let b = BlitRenderPass(
              //                label: "blit \(sfx.name!) in \(shaderName)",
              //                pairs:
              //              )
              //              pipelinePasses.append(b)

              pipelinePasses.append(p)
              lastRender = p.resolveTextures.1
            } else {
              os_log("failed to create render pipeline pass for %s in %s", type:.error, sfx.name!, shaderName)
              return
            }
          }
        }
      }
    } else {
      if let vertexProgram = currentVertexFn("") ?? findFunction("flatVertexFn"),
        let fragmentProgram = currentFragmentFn("") ?? findFunction("passthruFragmentFn"),
        let p = RenderPipelinePass(
          label: "\(shaderName)",
          viCount: (4, 1),
          flags: 0,
          canvasSize: canvasSize,
          topology: .triangleStrip,
          computeBuffer : nil,
          functions: (vertexProgram, fragmentProgram),
          isFinal: true) {
        pipelinePasses.append(p)
        lastRender = p.resolveTextures.1
      } else {
        os_log("failed to create render pipeline pass for %s", type:.error, shaderName)
        return
      }
    }





  }




  func currentVertexFn(_ sfx : String) -> MTLFunction? {
    let lun = "\(shaderName)___\(sfx)___Vertex";
    return findFunction(lun);
  }

  func currentFragmentFn(_ sfx : String) -> MTLFunction? {
    let lun = "\(shaderName)___\(sfx)___Fragment";
    return findFunction(lun)
  }


}
