import pyperf
import ctypes
import os

# Load your compiled C
craytrace = ctypes.CDLL(os.path.abspath("CraytraceLib.dll"))

DEFAULT_WIDTH = 800
DEFAULT_HEIGHT = 800
EPSILON = 0.00001


#<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<># 
#                                                                                            # 
#                                                                                            # 
#                              CTYPES STRUCT DEFINITIONS                                     # 
#                                                                                            # 
#                                                                                            # 
#<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<># 


class Vector(ctypes.Structure):
    _fields_ = [("x", ctypes.c_double), ("y", ctypes.c_double), ("z", ctypes.c_double)]

Vector.UP = Vector(0.0, 1.0, 0.0)

class Point(ctypes.Structure):
    _fields_ = [("x", ctypes.c_double), ("y", ctypes.c_double), ("z", ctypes.c_double)]

class Double_Color(ctypes.Structure):
    _fields_ = [("r", ctypes.c_double), ("g", ctypes.c_double), ("b", ctypes.c_double)]

class Sphere(ctypes.Structure):
    _fields_ = [("centre", Point), ("radius", ctypes.c_double)]

class Halfspace(ctypes.Structure):
    _fields_ = [("point", Point), ("normal", Vector)]

class SimpleSurface(ctypes.Structure):
    _fields_ = [
        ("base_color", Double_Color),
        ("specular_coefficient", ctypes.c_double),
        ("lambert_coefficient", ctypes.c_double),
        ("ambient_coefficient", ctypes.c_double)
    ]
    def __init__(self, baseColour=(1.0, 1.0, 1.0), **kwargs):
        super().__init__(
            Double_Color(baseColour[0], baseColour[1], baseColour[2]),
            kwargs.get('specularCoefficient', 0.2),
            kwargs.get('lambertCoefficient', 0.6),
            1.0 - kwargs.get('specularCoefficient', 0.2) - kwargs.get('lambertCoefficient', 0.6)
        )

class CheckerboardSurface(ctypes.Structure):
    _fields_ = [
        ("first_color", Double_Color),
        ("second_color", Double_Color),
        ("specular_coefficient", ctypes.c_double),
        ("lambert_coefficient", ctypes.c_double),
        ("ambient_coefficient", ctypes.c_double),
        ("check_size", ctypes.c_double)
    ]
    def __init__(self, **kwargs):
        bc = kwargs.get('baseColour', (1.0, 1.0, 1.0))
        oc = kwargs.get('otherColour', (0.0, 0.0, 0.0))
        super().__init__(
            Double_Color(bc[0], bc[1], bc[2]),
            Double_Color(oc[0], oc[1], oc[2]),
            kwargs.get('specularCoefficient', 0.2),
            kwargs.get('lambertCoefficient', 0.6),
            1.0 - kwargs.get('specularCoefficient', 0.2) - kwargs.get('lambertCoefficient', 0.6),
            kwargs.get('checkSize', 1.0)
        )

class CanvasStruct(ctypes.Structure):
    _fields_ = [("width", ctypes.c_int), ("height", ctypes.c_int), ("bytes", ctypes.POINTER(ctypes.c_ubyte))]


#<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>#
#                                                                                            #
#                                                                                            #
#                                 C FUNCTION SIGNATURES                                      #
#                                                                                            #
#                                                                                            #
#<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>#


craytrace.init_canvas.argtypes = [ctypes.POINTER(CanvasStruct), ctypes.c_int, ctypes.c_int]
craytrace.write_ppm.argtypes = [ctypes.POINTER(CanvasStruct), ctypes.c_char_p]
craytrace.free_canvas.argtypes = [ctypes.POINTER(CanvasStruct)]

craytrace.init_scene.argtypes = [ctypes.c_void_p]
craytrace.look_at.argtypes = [ctypes.c_void_p, ctypes.POINTER(Point)]
craytrace.add_light.argtypes = [ctypes.c_void_p, ctypes.POINTER(Point)]

craytrace.add_to_simple_spheres.argtypes = [ctypes.c_void_p, ctypes.POINTER(Sphere), ctypes.POINTER(SimpleSurface)]
craytrace.add_to_checker_spheres.argtypes = [ctypes.c_void_p, ctypes.POINTER(Sphere), ctypes.POINTER(CheckerboardSurface)]
craytrace.add_to_simple_halfspaces.argtypes = [ctypes.c_void_p, ctypes.POINTER(Halfspace), ctypes.POINTER(SimpleSurface)]
craytrace.add_to_checker_halfspaces.argtypes = [ctypes.c_void_p, ctypes.POINTER(Halfspace), ctypes.POINTER(CheckerboardSurface)]

craytrace.render.argtypes = [ctypes.c_void_p, ctypes.POINTER(CanvasStruct)]

# ==========================================
# PYTHON API CLASSES
# ==========================================
class Canvas:
    def __init__(self, width, height):
        self._obj = CanvasStruct()
        craytrace.init_canvas(ctypes.byref(self._obj), width, height)

    def write_ppm(self, filename):
        craytrace.write_ppm(ctypes.byref(self._obj), filename.encode('utf-8'))

    def __del__(self):
        craytrace.free_canvas(ctypes.byref(self._obj))

class Scene:
    def __init__(self):
        # Allocate a large enough byte buffer to hold the inline C arrays cleanly
        self._obj = ctypes.create_string_buffer(8192)
        craytrace.init_scene(self._obj)

    def lookAt(self, p):
        craytrace.look_at(self._obj, ctypes.byref(p))

    def addLight(self, p):
        craytrace.add_light(self._obj, ctypes.byref(p))

    def addObject(self, shape, surface):
        if isinstance(shape, Sphere):
            if isinstance(surface, SimpleSurface):
                 craytrace.add_to_simple_spheres(self._obj, ctypes.byref(shape), ctypes.byref(surface))
            elif isinstance(surface, CheckerboardSurface):
                 craytrace.add_to_checker_spheres(self._obj, ctypes.byref(shape), ctypes.byref(surface))
        elif isinstance(shape, Halfspace):
            if isinstance(surface, SimpleSurface):
                 craytrace.add_to_simple_halfspaces(self._obj, ctypes.byref(shape), ctypes.byref(surface))
            elif isinstance(surface, CheckerboardSurface):
                 craytrace.add_to_checker_halfspaces(self._obj, ctypes.byref(shape), ctypes.byref(surface))

    def render(self, canvas):
         craytrace.render(self._obj, ctypes.byref(canvas._obj))


'''
------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------
------------------------------------------------------------------------
------------------------------------------------------
------------------------------------
------------------
------------------
------------------------------------
------------------------------------------------------
------------------------------------------------------------------------
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------
'''


def bench_raytrace(loops, width, height, filename):
    range_it = range(loops)
    t0 = pyperf.perf_counter()

    for i in range_it:
        canvas = Canvas(width, height)
        s = Scene()
        s.addLight(Point(30, 30, 10))
        s.addLight(Point(-10, 100, 30))
        s.lookAt(Point(0, 3, 0))
        s.addObject(Sphere(Point(1, 3, -10), 2),
                    SimpleSurface(baseColour=(1, 1, 0)))
        for y in range(6):      # add 6 spheres  
            s.addObject(Sphere(Point(-3 - y * 0.4, 2.3, -5), 0.4),
                        SimpleSurface(baseColour=(y / 6.0, 1 - y / 6.0, 0.5)))
        s.addObject(Halfspace(Point(0, 0, 0), Vector.UP),
                    CheckerboardSurface())
        s.render(canvas)

    dt = pyperf.perf_counter() - t0

    if filename:
        canvas.write_ppm(filename)
    return dt


def add_cmdline_args(cmd, args):
    cmd.append("--width=%s" % args.width)
    cmd.append("--height=%s" % args.height)
    if args.filename:
        cmd.extend(("--filename", args.filename))


if __name__ == "__main__":
    runner = pyperf.Runner(add_cmdline_args=add_cmdline_args)
    cmd = runner.argparser
    cmd.add_argument("--width",
                     type=int, default=DEFAULT_WIDTH,
                     help="Image width (default: %s)" % DEFAULT_WIDTH)
    cmd.add_argument("--height",
                     type=int, default=DEFAULT_HEIGHT,
                     help="Image height (default: %s)" % DEFAULT_HEIGHT)
    cmd.add_argument("--filename", metavar="FILENAME.PPM",
                     help="Output filename of the PPM picture")

    args = runner.parse_args()
    runner.metadata['description'] = "Simple raytracer"
    runner.metadata['raytrace_width'] = args.width
    runner.metadata['raytrace_height'] = args.height

    runner.bench_time_func('raytrace', bench_raytrace,
                           args.width, args.height,
                           "my_render.ppm")