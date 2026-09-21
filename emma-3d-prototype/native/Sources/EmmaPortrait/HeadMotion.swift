import Foundation
import SceneKit

enum HeadMotion {
    static func delta(_ index: Int, _ x: Double, _ y: Double) -> SCNVector3 {
        func g(_ cx: Double, _ cy: Double, _ sx: Double, _ sy: Double) -> Double {
            exp(-pow((x-cx)/sx,2)-pow((y-cy)/sy,2))
        }
        if index < 2 {
            let cx = index == 0 ? -0.25 : 0.18, cy = index == 0 ? 0.18 : 0.12
            let w = g(cx,cy,0.063,0.082)
            return SCNVector3(0,Float(-(y-cy)*0.96*w),Float(-0.006*w))
        }
        if index < 4 {
            let side = index == 2 ? -1.0 : 1.0
            let w = g(side*0.46,0.66,0.27,0.36)*min(1,max(0,(y-0.28)/0.2))
            return SCNVector3(Float(side*(y-0.3)*0.09*w),Float(-abs(x-side*0.28)*0.065*w),Float(0.035*w))
        }
        let w = g(-0.08,-0.27,0.20,0.13)
        return SCNVector3(0,Float(-0.035*w),Float(0.012*w))
    }
    static func pose(_ t: Double, _ state: EmmaPortraitState, _ level: Double) -> (weights: [Double], angles: SCNVector3, scale: Float) {
        func pulse(_ phase: Double, _ start: Double, _ duration: Double) -> Double {
            let a = (phase-start)/duration
            return a >= 0 && a < 1 ? pow(sin(a * .pi),2) : 0
        }
        let cycle = t.truncatingRemainder(dividingBy:7.8)
        let blink = max(pulse(cycle,2.6,0.21),pulse(cycle,6.1,0.19),pulse(cycle,6.44,0.17))
        let listening = state == .listening, thinking = state == .thinking
        let jaw = state == .speaking ? min(1,max(0,level))*(0.72+0.28*sin(t*17)) : 0
        let left = (listening ? 0.48 : 0.1)+pulse(t.truncatingRemainder(dividingBy:11.2),4.5,0.48)*0.55
        let right = (listening ? 0.35 : 0.08)+pulse((t+1.7).truncatingRemainder(dividingBy:13),5,0.5)*0.5
        let angles = SCNVector3(Float(sin(t*0.73)*0.012+(listening ? -0.03 : 0)+jaw*0.007),Float(sin(t*0.43)*0.026+(thinking ? 0.035 : 0)),Float(sin(t*0.58)*0.014+(listening ? -0.06 : thinking ? 0.028 : 0)))
        return ([blink,blink*0.98,left,right,jaw],angles,Float(1+sin(t*1.5)*0.003))
    }
}
