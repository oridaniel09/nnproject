"""
This file contains definitions for a simple raytracer.
Copyright Callum and Tony Garnock-Jones, 2008.

This file may be freely redistributed under the MIT license,
http://www.opensource.org/licenses/mit-license.php

From http://www.lshift.net/blog/2008/10/29/toy-raytracer-in-python
"""

# Notes by Or Sasson, suggestions for SOFTWARE optimization (or at least not doing the hardware verilog suggestion), stuff that can be optimized by the CPU

# Important - who spells color with a u? Have they got no shame?

import array
import math

import argparse
import time

#import pyperf


DEFAULT_WIDTH = 800
DEFAULT_HEIGHT = 800
EPSILON = 0.00001


class Vector(object):   # vectorization

    def __init__(self, initx, inity, initz):
        self.x = initx
        self.y = inity
        self.z = initz

    def __str__(self):
        return '(%s,%s,%s)' % (self.x, self.y, self.z)

    def __repr__(self):
        return 'Vector(%s,%s,%s)' % (self.x, self.y, self.z)

    def magnitude(self):
        return math.sqrt(self.dot(self))

    def __add__(self, other):
        if other.isPoint():
            return Point(self.x + other.x, self.y + other.y, self.z + other.z)
        else:
            return Vector(self.x + other.x, self.y + other.y, self.z + other.z)

    def __sub__(self, other):
        other.mustBeVector()
        return Vector(self.x - other.x, self.y - other.y, self.z - other.z)

    def scale(self, factor):
        return Vector(factor * self.x, factor * self.y, factor * self.z)

    def dot(self, other):
        other.mustBeVector()
        return (self.x * other.x) + (self.y * other.y) + (self.z * other.z)

    def cross(self, other):
        other.mustBeVector()
        return Vector(self.y * other.z - self.z * other.y,
                      self.z * other.x - self.x * other.z,
                      self.x * other.y - self.y * other.x)

    def normalized(self):
        return self.scale(1.0 / self.magnitude())

    def negated(self):
        return self.scale(-1)

    def __eq__(self, other):
        return (self.x == other.x) and (self.y == other.y) and (self.z == other.z)

    def isVector(self):
        return True

    def isPoint(self):
        return False

    def mustBeVector(self):
        return self

    def mustBePoint(self):
        raise 'Vectors are not points!'

    def reflectThrough(self, normal):
        d = normal.scale(self.dot(normal))
        return self - d.scale(2)


Vector.ZERO = Vector(0, 0, 0)
Vector.RIGHT = Vector(1, 0, 0)
Vector.UP = Vector(0, 1, 0)
Vector.OUT = Vector(0, 0, 1)

assert Vector.RIGHT.reflectThrough(Vector.UP) == Vector.RIGHT
assert Vector(-1, -1, 0).reflectThrough(Vector.UP) == Vector(-1, 1, 0)


class Point(object):    # vectorization

    def __init__(self, initx, inity, initz):
        self.x = initx
        self.y = inity
        self.z = initz

    def __str__(self):
        return '(%s,%s,%s)' % (self.x, self.y, self.z)

    def __repr__(self):
        return 'Point(%s,%s,%s)' % (self.x, self.y, self.z)

    def __add__(self, other):
        other.mustBeVector()
        return Point(self.x + other.x, self.y + other.y, self.z + other.z)

    def __sub__(self, other):
        if other.isPoint():
            return Vector(self.x - other.x, self.y - other.y, self.z - other.z)
        else:
            return Point(self.x - other.x, self.y - other.y, self.z - other.z)

    def isVector(self):
        return False

    def isPoint(self):
        return True

    def mustBeVector(self):
        raise 'Points are not vectors!'

    def mustBePoint(self):
        return self


class Sphere(object):

    def __init__(self, centre, radius):
        centre.mustBePoint()
        self.centre = centre
        self.radius = radius

    def __repr__(self):
        return 'Sphere(%s,%s)' % (repr(self.centre), self.radius)

    def intersectionTime(self, ray):
        cp = self.centre - ray.point
        v = cp.dot(ray.vector)  # basically how much the light from that
        discriminant = (self.radius * self.radius) - (cp.dot(cp) - v * v)
        if discriminant < 0:
            return None
        else:
            return v - math.sqrt(discriminant)

    def normalAt(self, p):
        return (p - self.centre).normalized()


class Halfspace(object):    # a plane

    def __init__(self, point, normal):
        self.point = point
        self.normal = normal.normalized()

    def __repr__(self):
        return 'Halfspace(%s,%s)' % (repr(self.point), repr(self.normal))

    def intersectionTime(self, ray):
        v = ray.vector.dot(self.normal)
        if v:
            return 1 / -v
        else:
            return None

    def normalAt(self, p):
        return self.normal


class Ray(object):

    def __init__(self, point, vector):
        self.point = point
        self.vector = vector.normalized()

    def __repr__(self):
        return 'Ray(%s,%s)' % (repr(self.point), repr(self.vector))

    def pointAtTime(self, t):
        return self.point + self.vector.scale(t)


Point.ZERO = Point(0, 0, 0)


class Canvas(object):

    def __init__(self, width, height):
        self.bytes = array.array('B', [0] * (width * height * 3))
        for i in range(width * height):     # a blue background
            self.bytes[i * 3 + 2] = 255
        self.width = width
        self.height = height

    def plot(self, x, y, r, g, b):      # change a color of a pixel (in the 2D screen)
        i = ((self.height - y - 1) * self.width + x) * 3        # mult can be change to shift by 8 and sub 1
        self.bytes[i] = max(0, min(255, int(r * 255)))
        self.bytes[i + 1] = max(0, min(255, int(g * 255)))
        self.bytes[i + 2] = max(0, min(255, int(b * 255)))

    def write_ppm(self, filename):      # get a file
        header = 'P6 %d %d 255\n' % (self.width, self.height)
        with open(filename, "wb") as fp:
            fp.write(header.encode('ascii'))    # write the header
            fp.write(self.bytes.tobytes())      # write the whole pixels (remember self.bytes holds the image (array of pixels)


def firstIntersection(intersections):   # branchless logic?
    result = None
    for i in intersections:
        candidateT = i[1]
        if candidateT is not None and candidateT > -EPSILON:
            if result is None or candidateT < result[1]:
                result = i
    return result


class Scene(object):

    def __init__(self):
        self.objects = []
        self.lightPoints = []
        self.position = Point(0, 1.8, 10)
        self.lookingAt = Point.ZERO
        self.fieldOfView = 45
        self.recursionDepth = 0

    def moveTo(self, p):
        self.position = p

    def lookAt(self, p):
        self.lookingAt = p

    def addObject(self, object, surface):
        self.objects.append((object, surface))

    def addLight(self, p):
        self.lightPoints.append(p)

    def render(self, canvas):
        fovRadians = math.pi * (self.fieldOfView / 2.0) / 180.0     # redundant division, change to pi * (FOV / 360.0)
        halfWidth = math.tan(fovRadians)        # optimize trigo calcs (accuracy trade)
        halfHeight = 0.75 * halfWidth           # multiply by 3 and shift right twice
        width = halfWidth * 2                   # shift left
        height = halfHeight * 2                 # shift left, or (halfWidth *3) >> 1 and remove two lines above
        pixelWidth = width / (canvas.width - 1)
        pixelHeight = height / (canvas.height - 1)

        eye = Ray(self.position, self.lookingAt - self.position)
        vpRight = eye.vector.cross(Vector.UP).normalized()
        vpUp = vpRight.cross(eye.vector).normalized()

        for y in range(canvas.height):  # check if access order is continuous, bring ycomp out to main loop, anyway vectorization
            for x in range(canvas.width):
                xcomp = vpRight.scale(x * pixelWidth - halfWidth)   # getting a vector from a pixel to the model / scene, to know its color
                ycomp = vpUp.scale(y * pixelHeight - halfHeight)
                ray = Ray(eye.point, eye.vector + xcomp + ycomp)    # can we reuse the same object instead of creating tons of them?
                colour = self.rayColour(ray)
                canvas.plot(x, y, *colour)  # a size is only a byte, surely we can vectorize and even more

    def rayColour(self, ray):   # shooting (cursed technique) reversal light and tracking what object it hits, can bounce, but not more than the maximum recursion depth (3)
        if self.recursionDepth > 3:
            return (0, 0, 0)
        try:    # getting the color of the first object the ray hits
            self.recursionDepth = self.recursionDepth + 1
            intersections = [(o, o.intersectionTime(ray), s)
                             for (o, s) in self.objects]
            i = firstIntersection(intersections)
            if i is None:
                return (0, 0, 0)  # the background colour
            else:
                (o, t, s) = i
                p = ray.pointAtTime(t)
                return s.colourAt(self, ray, p, o.normalAt(p))  # reflecting the light at surface's function - colourAt
        finally:
            self.recursionDepth = self.recursionDepth - 1

    def _lightIsVisible(self, l, p):
        for (o, s) in self.objects:
            t = o.intersectionTime(Ray(p, l - p))
            if t is not None and t > EPSILON:
                return False
        return True

    def visibleLights(self, p):
        result = []
        for l in self.lightPoints:
            if self._lightIsVisible(l, p):
                result.append(l)
        return result


def addColours(a, scale, b):    # vectorization, inline assembly?
    return (a[0] + scale * b[0],
            a[1] + scale * b[1],
            a[2] + scale * b[2])


class SimpleSurface(object):

    def __init__(self, **kwargs):
        self.baseColour = kwargs.get('baseColour', (1, 1, 1))
        self.specularCoefficient = kwargs.get('specularCoefficient', 0.2)   # how much the beam from a light source reflected on the surface aligns with your angle of view
        self.lambertCoefficient = kwargs.get('lambertCoefficient', 0.6)     # how rough the surface is
        self.ambientCoefficient = 1.0 - self.specularCoefficient - self.lambertCoefficient # how uniform the light is?

    def baseColourAt(self, p):
        return self.baseColour

    def colourAt(self, scene, ray, p, normal):
        b = self.baseColourAt(p)

        c = (0, 0, 0)                   # branch-less logic?
        if self.specularCoefficient > 0:
            reflectedRay = Ray(p, ray.vector.reflectThrough(normal))    # reflect the light beam, take into consideration the reflection coefficient
            reflectedColour = scene.rayColour(reflectedRay)     # searching for the color itself
            c = addColours(c, self.specularCoefficient, reflectedColour)

        if self.lambertCoefficient > 0:
            lambertAmount = 0
            for lightPoint in scene.visibleLights(p):
                contribution = (lightPoint - p).normalized().dot(normal)
                if contribution > 0:
                    lambertAmount = lambertAmount + contribution
            lambertAmount = min(1, lambertAmount)
            c = addColours(c, self.lambertCoefficient * lambertAmount, b)

        if self.ambientCoefficient > 0:
            c = addColours(c, self.ambientCoefficient, b)

        return c


class CheckerboardSurface(SimpleSurface):

    def __init__(self, **kwargs):
        SimpleSurface.__init__(self, **kwargs)
        self.otherColour = kwargs.get('otherColour', (0, 0, 0))
        self.checkSize = kwargs.get('checkSize', 1)

    def baseColourAt(self, p):
        v = p - Point.ZERO
        v.scale(1.0 / self.checkSize)
        if ((int(abs(v.x) + 0.5)    # branch-less
             + int(abs(v.y) + 0.5)
             + int(abs(v.z) + 0.5)) % 2):
            return self.otherColour
        else:
            return self.baseColour


def bench_raytrace(loops, width, height, filename):
    range_it = range(loops)
    t0 = time.perf_counter()

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

    dt = time.perf_counter() - t0

    if filename:
        canvas.write_ppm(filename)
    return dt

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Simple raytracer")
    parser.add_argument("--width", type=int, default=DEFAULT_WIDTH,
                        help=f"Image width (default: {DEFAULT_WIDTH})")
    parser.add_argument("--height", type=int, default=DEFAULT_HEIGHT,
                        help=f"Image height (default: {DEFAULT_HEIGHT})")
    parser.add_argument("--filename", metavar="FILENAME.PPM", default="my_render.ppm",
                        help="Output filename of the PPM picture")
    parser.add_argument("--loops", type=int, default=1,
                        help="Number of rendering iterations to run (default: 1)")

    args = parser.parse_args()

    print(f"Running raytracer ({args.width}x{args.height}) for {args.loops} loop(s)...")

    elapsed_time = bench_raytrace(args.loops, args.width, args.height, args.filename)

    print(f"Total time: {elapsed_time:.4f} seconds")
    if args.loops > 1:
        print(f"Average time per loop: {elapsed_time / args.loops:.4f} seconds")