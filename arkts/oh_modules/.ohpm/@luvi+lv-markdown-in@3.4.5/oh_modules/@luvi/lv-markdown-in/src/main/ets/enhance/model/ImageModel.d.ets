// @keepTs
// @ts-nocheck
import matrix4 from "@ohos.matrix4";
import window from "@ohos.window";
import image from "@ohos.multimedia.image";
@Observed
export declare class ImageModel {
    matrix: matrix4.Matrix4Transit;
    curScale: number;
    curOffsetX: number;
    curOffsetY: number;
    lastScale: number;
    lastOffsetX: number;
    lastOffsetY: number;
    minScale: number;
    maxScale: number;
    defaultScaleValue: number;
    maxOffsetX: number;
    minOffsetX: number;
    maxOffsetY: number;
    minOffsetY: number;
    centerX: number;
    centerY: number;
    center: number[];
    componentHeight: number;
    componentWidth: number;
    imageWidth: number;
    imageHeight: number | undefined;
    isDisableSwipe: boolean;
    constructor(m87?: matrix4.Matrix4Transit, n87?: number, o87?: number, p87?: number, q87?: number, r87?: number, s87?: number, t87?: number, u87?: number, v87?: number, w87?: number, x87?: number, y87?: number, z87?: number, a88?: number, b88?: number, c88?: [
        number,
        number
    ], d88?: number, e88?: number, f88?: number, g88?: number | undefined, h88?: boolean);
    gestureEnd(): void;
    imageReset(): void;
    offsetReset(): void;
    windowSize(): void;
    pictureScaling(i87: number): void;
    evaluateOffsetRange(): void;
    evaluateCenter(a87: number, b87: number): [
        number,
        number
    ];
    calcFitScaleRatio(x86: image.Size, y86: window.Size): number;
    panGestureUpdate(w86: GestureEvent): boolean;
    pinchGestureStart(v86: GestureEvent): void;
    pictureBoundaryRestriction(): void;
    pinchGestureUpdate(u86: GestureEvent): boolean;
    pinchGestureEnd(): void;
    doubleTapGesture(s86: GestureEvent): boolean;
    onScale(p86: number, q86: number, r86: number): void;
}
/**
 * Status bar title and icon.
 */
export declare class ImageInfo {
    icon?: Resource;
    name?: Resource;
    constructor(n86: Resource, o86: Resource);
}
