/*
This file contains definitions for a simple raytracer.
Copyright Callum and Tony Garnock-Jones, 2008.

This file may be freely redistributed under the MIT license,
http://www.opensource.org/licenses/mit-license.php

From http://www.lshift.net/blog/2008/10/29/toy-raytracer-in-python
"""

# Notes by Or Sasson, suggestions for SOFTWARE optimization (or at least not doing the hardware verilog suggestion), stuff that can be optimized by the CPU

# Important - who spells color with a u? Have they got no shame?
*/

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <stdbool.h>
#include <stdint.h>


# define EPSILON 0.00001


//<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>\\
//                                                                                            \\
//                                                                                            \\
//                                   Structs definitions                                      \\
//                                                                                            \\
//                                                                                            \\
//<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>\\


typedef struct{
    double r, g, b;
} Double_Color;

typedef struct {
    double x;
    double y;
    double z;
} Vector;

typedef struct {
    double x;
    double y;
    double z;
} Point;

typedef struct {
    Double_Color base_color;
    double specular_coefficient;
    double lambert_coefficient;
    double ambient_coefficient;
} Simple_Surface;

typedef struct {
    Double_Color first_color;
    Double_Color second_color;
    double specular_coefficient;
    double lambert_coefficient;
    double ambient_coefficient;
    double check_size;
} Checkerboard_Surface;

typedef struct {
    Point centre;
    double radius;
} Sphere;

typedef struct {
    Point point;
    Vector normal;
} Halfspace;

typedef struct {
    Point point;
    Vector vector;
} Ray;

typedef struct {
    int width;
    int height;
    unsigned char* bytes;
} Canvas;

typedef struct {
    Sphere sphere;
    Simple_Surface surface;
} Simple_Sphere;

typedef struct {
    Halfspace halfspace;
    Simple_Surface surface;
} Simple_Halfspace;

typedef struct {
    Sphere sphere;
    Checkerboard_Surface surface;
} Checker_Sphere;

typedef struct {
    Halfspace halfspace;
    Checkerboard_Surface surface;
} Checker_Halfspace;

typedef struct {    //using a size of 10 because the benchmark never uses more than 6+1=7 for each type
    Simple_Sphere simple_spheres[10];
    int simple_spheres_count;       // how many simple spheres currently exist
    Simple_Halfspace simple_halfspaces[10];
    int simple_halfspaces_count;    // how many simple halfspaces currently exist
    Checker_Sphere checker_spheres[10];
    int checker_spheres_count;      // how many checker spheres currently exist
    Checker_Halfspace checker_halfspaces[10];
    int checker_halfspaces_count;   // how many checker halfspaces currently exist
    Point light_points[10];
    int light_points_count;
    Point position;
    Point looking_at;
    double field_of_view;
    char recursion_depth;
} Scene;

typedef struct{
    Simple_Sphere min_simple_sphere;
    Simple_Halfspace min_simple_halfspace;
    Checker_Sphere min_checkerboard_sphere;
    Checker_Halfspace min_checkerboard_halfspace;
    char min_type;    // 0 - no intersection, 1 - simple sphere, 2 - checkerboard sphere, 3 - simple halfspace, 4 - checkerboard halfspace
    double min_time;
} Min_Packer;

//<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>\\
//                                                                                            \\
//                                                                                            \\
//                              Recreating the Vector class in C                              \\
//                                                                                            \\
//                                                                                            \\
//<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>\\


// Initialize a vector with given x, y, z values
void init_vector(Vector* v, const double x, const double y, const double z) {
    v->x = x;
    v->y = y;
    v->z = z;
}

// no need in C to define __str__ and __repr__, they are never used anyway, but we can define a print function for debugging
void print_vector(const Vector* v) {
    printf("(%f, %f, %f)\n", v->x, v->y, v->z);
}

double magnitude(const Vector* v) {
    return sqrt(v->x * v->x + v->y * v->y + v->z * v->z);
}

// Create a new vector that is the sum of two vectors
Vector add_vectors_creation(const Vector* v1, const Vector* v2) {
    Vector result;
    init_vector(&result, v1->x + v2->x, v1->y + v2->y, v1->z + v2->z);
    return result;
}

// In-place addition of two vectors, storing the result in a pre-allocated vector
void add_vectors_inplace(const Vector* v1, const Vector* v2, Vector* result) {
    result->x = v1->x + v2->x;
    result->y = v1->y + v2->y;
    result->z = v1->z + v2->z;
}

// Create a new vector that is the subtraction of two vectors
Vector sub_vectors_creation(const Vector* v1, const Vector* v2) {
    Vector result;
    init_vector(&result, v1->x - v2->x, v1->y - v2->y, v1->z - v2->z);
    return result;
}

// In-place addition of two vectors, storing the result in a pre-allocated vector
void sub_vectors_inplace(const Vector* v1, const Vector* v2, Vector* result) {
    result->x = v1->x - v2->x;
    result->y = v1->y - v2->y;
    result->z = v1->z - v2->z;
}

Vector scale_vector_creation(const Vector* v, const double factor) {
    Vector result;
    init_vector(&result, factor * v->x, factor * v->y, factor * v->z);
    return result;
}

void scale_vector_inplace(Vector* v, const double factor) {
    v->x = factor * v->x;
    v->y = factor * v->y;
    v->z = factor * v->z;
}

double dot_product(const Vector* v1, const Vector* v2) {
    return (v1->x * v2->x) + (v1->y * v2->y) + (v1->z * v2->z);
}

void dot_product_inplace(const Vector* v1, const Vector* v2, double* result) {
    *result = (v1->x * v2->x) + (v1->y * v2->y) + (v1->z * v2->z);
}

Vector cross_product(const Vector* v1, const Vector* v2) {
    Vector result;
    init_vector(&result, v1->y * v2->z - v1->z * v2->y,
                        v1->z * v2->x - v1->x * v2->z,
                        v1->x * v2->y - v1->y * v2->x);
    return result;
}

void cross_product_inplace(const Vector* v1, const Vector* v2, Vector* result) {
    result->x = v1->y * v2->z - v1->z * v2->y;
    result->y = v1->z * v2->x - v1->x * v2->z;
    result->z = v1->x * v2->y - v1->y * v2->x;
}

void normalize_vector(Vector* v) {
    double mag = magnitude(v);
    if (mag > 0) {
        scale_vector_inplace(v, 1.0 / mag);
    }
}

void negated(Vector* v) {
    v->x = -v->x;
    v->y = -v->y;
    v->z = -v->z;
}

bool are_vectors_equal(const Vector* v1, const Vector* v2) {
    return (v1->x == v2->x) && (v1->y == v2->y) && (v1->z == v2->z);
}

Vector reflect_vector_creation(const Vector* v, const Vector* normal) {
    Vector result = *normal;
    double double_dot = 2.0 * dot_product(v, normal);
    scale_vector_inplace(&result, double_dot);
    sub_vectors_inplace(v, &result, &result);
    return result;
}

#define Vector_ZERO (Vector){0, 0, 0}
#define Vector_RIGHT (Vector){1, 0, 0}
#define Vector_UP (Vector){0, 1, 0}
/* remnants
Vector.ZERO = Vector(0, 0, 0)
Vector.RIGHT = Vector(1, 0, 0)
Vector.UP = Vector(0, 1, 0)
Vector.OUT = Vector(0, 0, 1)


assert Vector.RIGHT.reflectThrough(Vector.UP) == Vector.RIGHT
assert Vector(-1, -1, 0).reflectThrough(Vector.UP) == Vector(-1, 1, 0)
*/

//<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>\\
//                                                                                            \\
//                                                                                            \\
//                              Recreating the Point class in C                               \\
//                                                                                            \\
//                                                                                            \\
//<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>\\


void init_point(Point* p, double x, double y, double z) {
    p->x = x;
    p->y = y;
    p->z = z;
}

// Since we cannot add points (no geometric meaning), we can only add a point and a vector, which results in a new point
Point add_vector_to_point_creation(const Vector* v, const Point* p) {
    Point result;
    init_point(&result, p->x + v->x, p->y + v->y, p->z + v->z);
    return result;
}

void add_vector_to_point_inplace(const Vector* v, const Point* p, Point* result) {
    result->x = p->x + v->x;
    result->y = p->y + v->y;
    result->z = p->z + v->z;
}

// the subtraction of two points is a vector, not a point, so we need to return a vector instead of a point
Vector vector_from_1_to_2_creation(const Point* p1, const Point* p2) {
    Vector result;
    init_vector(&result, p2->x - p1->x, p2->y - p1->y, p2->z - p1->z);
    return result;
}

void vector_from_1_to_2_inplace(const Point* p1, const Point* p2, Vector* result) {
    result->x = p2->x - p1->x;
    result->y = p2->y - p1->y;
    result->z = p2->z - p1->z;
}

void add_colors_inplace(Double_Color* a, double scale, Double_Color* b, Double_Color* result){    // vectorization, inline assembly?
    result->r = a->r + (scale * b->r);
    result->g = a->g + (scale * b->g);
    result->b = a->b + (scale * b->b);
}

#define Point_ZERO (Point){0, 0, 0}


//<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>\\
//                                                                                            \\
//                                                                                            \\
//                              Recreating the Sphere class in C                              \\
//                                                                                            \\
//                                                                                            \\
//<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>\\


void init_sphere(Sphere* s, const Point* centre, double radius){
    s->centre = *centre;
    s->radius = radius;
}

double intersection_time_sphere(const Sphere* s, const Ray* ray){
    Vector beam_direction = vector_from_1_to_2_creation(&ray->point, &s->centre);
    double dot_projection = dot_product(&beam_direction, &ray->vector);  // how much the light from that point is aligned with the direction of the ray
    double discriminant = (s->radius * s->radius) - (dot_product(&beam_direction, &beam_direction) - dot_projection * dot_projection);
    if (discriminant < 0) {
        return -1.0; // no intersection
    }
    return dot_projection - sqrt(discriminant);

}

Vector normal_at(const Sphere* s, const Point* p){
    Vector normal = vector_from_1_to_2_creation(&s->centre, p);
    normalize_vector(&normal);
    return normal;
}


//<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>\\
//                                                                                            \\
//                                                                                            \\
//                              Recreating the Half-Space class in C                          \\
//                                                                                            \\
//                                                                                            \\
//<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>\\


void init_halfspace(Halfspace* h, const Point* point, const Vector* normal){
    h->point = *point;
    h->normal = *normal;
    normalize_vector(&h->normal);
}


double intersection_time_halfspace(const Halfspace* h, const Ray* ray){
    double v = dot_product(&(h->normal),&(ray->vector));
    if (v != 0){
        return 1.0 / -v;
    } else {
        return -1.0; // no intersection
    }
}

Vector normal_at_halfspace(const Halfspace* h){
    return h->normal;
}

void normal_at_halfspace_inplace(const Halfspace* h, Vector* result){
    *result = h->normal;
}


//<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>\\
//                                                                                            \\
//                                                                                            \\
//                              Recreating the Ray class in C                                 \\
//                                                                                            \\
//                                                                                            \\
//<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>\\


void init_ray(Ray* ray, const Point* point, const Vector* vector){
    ray->point = *point;
    ray->vector = *vector;
    normalize_vector(&(ray->vector));
}

Point point_at_time_creation(const Ray* ray, double t){
    Vector scaled_vector = scale_vector_creation(&(ray->vector), t);
    Point point = add_vector_to_point_creation(&scaled_vector, &(ray->point));
    return point;
}

void point_at_time_inplace(const Ray* ray, double t, Point* result){
    Vector scaled_vector = scale_vector_creation(&(ray->vector), t);
    add_vector_to_point_inplace(&scaled_vector, &(ray->point), result);
}


/*
Point.ZERO = Point(0, 0, 0)
*/


//<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>\\
//                                                                                            \\
//                                                                                            \\
//                          Recreating the Surfaces classes in C                              \\
//                                                                                            \\
//                                                                                            \\
//<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>\\


// C can't have default arguments, but that's ok, the python code gives us this option
void init_simple_surface(Simple_Surface* simple_surface, int r, int g, int b, double specular_coefficient, double lambert_coefficient, double ambient_coefficient) {
    simple_surface->base_color.r = r;
    simple_surface->base_color.g = g;
    simple_surface->base_color.b = b;
    simple_surface->specular_coefficient = fabs(specular_coefficient);
    simple_surface->lambert_coefficient = fabs(lambert_coefficient);
    simple_surface->ambient_coefficient = 1.0 - fabs(specular_coefficient) - fabs(lambert_coefficient);
}

Double_Color base_color_at_simple_surface(const Simple_Surface* simple_surface) {
    return simple_surface->base_color;
}

// forward declaration for two-functions recursion
Double_Color ray_color(Scene* scene, const Ray* ray);
int is_light_visible(const Scene* scene, const Point* light_point, const Point* p);


Double_Color color_at_simple_surface(Scene* scene, const Simple_Surface* simple_surface, const Ray* ray, const Point* p, const Vector* normal) {
    Double_Color b = simple_surface->base_color, total_color = (Double_Color){0.0, 0.0, 0.0};       // branch-less logic?

    // specular contribution
    Ray reflected_ray;
    Vector reflected_vector = reflect_vector_creation(&(ray->vector), normal);
    init_ray(&reflected_ray, p, &reflected_vector);    // reflect the light beam
    Double_Color reflected_color = ray_color(scene, &reflected_ray);     // searching for the reflected color
    add_colors_inplace(&total_color, simple_surface->specular_coefficient, &reflected_color, &total_color);

    // lambert contribution
    double lambert_amount = 0;
    Vector light_direction;
    for (int i = 0; i < scene->light_points_count; i++){
        if (is_light_visible(scene, &(scene->light_points[i]), p) == 1){
            vector_from_1_to_2_inplace(p, &(scene->light_points[i]), &light_direction);
            normalize_vector(&light_direction);
            double contribution = dot_product(&light_direction, normal);
            if (contribution > 0){
                lambert_amount += contribution;
            }
        }   // else there's no contribution for this light source / point
    }
    lambert_amount = fmin(1.0, lambert_amount);
    add_colors_inplace(&total_color, simple_surface->lambert_coefficient * lambert_amount, &b, &total_color);

    // ambient contribution
    add_colors_inplace(&total_color, simple_surface->ambient_coefficient, &b, &total_color);

    return total_color;
}

//------\\------//------\\------//------\\------//------\\------//------\\------//

void init_checkerboard_surface(Checkerboard_Surface* checkerboard_surface, Double_Color first_color, Double_Color second_color,double specular_coefficient, double lambert_coefficient, double ambient_coefficient, double check_size) {
    checkerboard_surface->first_color = first_color;
    checkerboard_surface->second_color = second_color;
    checkerboard_surface->specular_coefficient = fabs(specular_coefficient);    // assuming fabs is floatABS() that can also apply to double
    checkerboard_surface->lambert_coefficient = fabs(lambert_coefficient);
    checkerboard_surface->ambient_coefficient = 1.0 - fabs(specular_coefficient) - fabs(lambert_coefficient);
    checkerboard_surface->check_size = check_size;
}

Double_Color base_color_at_checkerboard_surface(const Checkerboard_Surface* checkerboard_surface, const Point* p) {
    Vector v = vector_from_1_to_2_creation(&Point_ZERO, p);
    scale_vector_inplace(&v, 1.0 / checkerboard_surface->check_size);
    if (((int)(fabs(v.x) + 0.5) + (int)(fabs(v.y) + 0.5) + (int)(fabs(v.z) + 0.5)) % 2) {
        return checkerboard_surface->second_color;
    } else {
        return checkerboard_surface->first_color;
    }
    /*
    int modulo_indicator = ((int)(abs(v.x) + 0.5) + (int)(abs(v.y) + 0.5) + (int)(abs(v.z) + 0.5)) % 2;
    return modulo_indicator * checkerboard_surface->second_color + (1 - modulo_indicator) * checkerboard_surface->first_color;
    // is it really favorable? we switched simple conditions in multiplication
    */
}

Double_Color color_at_checkerboard_surface(Scene* scene, const Checkerboard_Surface* checkerboard_surface, const Ray* ray, const Point* p, const Vector* normal) {
    Double_Color b = base_color_at_checkerboard_surface(checkerboard_surface, p);
    Double_Color total_color = (Double_Color){0.0, 0.0, 0.0};

    // specular contribution
    Ray reflected_ray;
    Vector reflected_vector = reflect_vector_creation(&(ray->vector), normal);
    init_ray(&reflected_ray, p, &reflected_vector);    // reflect the light beam
    Double_Color reflected_color = ray_color(scene, &reflected_ray);     // searching for the reflected color
    add_colors_inplace(&total_color, checkerboard_surface->specular_coefficient, &reflected_color, &total_color);

    // lambert contribution
    double lambert_amount = 0;
    Vector light_direction;
    for (int i = 0; i < scene->light_points_count; i++){
        if (is_light_visible(scene, &(scene->light_points[i]), p) == 1){
            vector_from_1_to_2_inplace(p, &(scene->light_points[i]), &light_direction);
            normalize_vector(&light_direction);
            double contribution = dot_product(&light_direction, normal);
            if (contribution > 0){
                lambert_amount += contribution;
            }
        }   // else there's no contribution for this light source / point
    }
    lambert_amount = fmin(1.0, lambert_amount);
    add_colors_inplace(&total_color, checkerboard_surface->lambert_coefficient * lambert_amount, &b, &total_color);

    // ambient contribution
    add_colors_inplace(&total_color, checkerboard_surface->ambient_coefficient, &b, &total_color);

    return total_color;
}


//<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>\\
//                                                                                            \\
//                                                                                            \\
//                              Recreating the Canvas class in C                              \\
//                                                                                            \\
//                                                                                            \\
//<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>\\


void init_canvas(Canvas* canvas, int width, int height){
    canvas->width = width;
    canvas->height = height;
    canvas->bytes = (unsigned char*)malloc(width * height * 3); // allocating enough for 8 bits RGB values for each pixel
    for(int i = 0; i < width * height * 3; i += 3){
        canvas->bytes[i] = 0;        // red
        canvas->bytes[i + 1] = 0;    // green
        canvas->bytes[i + 2] = 255;  // blue
    }

}

// plot a pixel on the canvas at (x, y) with RGB values scaled to 0-255
void plot(const Canvas* canvas, int x, int y, double r, double g, double b){
    int i = ((canvas->height - y - 1) * canvas->width + x) * 3;        // mult can be changed to shift by 8 and sub 1 - not it's not, double is built different
    canvas->bytes[i] = (unsigned char)fmax(0, fmin(255, (r * 255)));
    canvas->bytes[i + 1] = (unsigned char)fmax(0, fmin(255, (g * 255)));
    canvas->bytes[i + 2] = (unsigned char)fmax(0, fmin(255, (b * 255)));
}

void free_canvas(Canvas* canvas){
    free(canvas->bytes);
    canvas->bytes = NULL;
}

void write_ppm(Canvas* canvas, const char* filename){
    FILE* fp = fopen(filename, "wb");
    if (fp == NULL) {
        perror("Error opening file");
        return;
    }
    fprintf(fp, "P6 %d %d 255\n", canvas->width, canvas->height);
    fwrite(canvas->bytes, sizeof(unsigned char), canvas->width * canvas->height * 3, fp);
    fclose(fp);
    
    // it's the last function to be called, so we can free the canvas memory here
    free_canvas(canvas);
}
/*
    def write_ppm(self, filename):      # get a file 
        header = 'P6 %d %d 255\n' % (self.width, self.height)
        with open(filename, "wb") as fp:
            fp.write(header.encode('ascii'))    # write the header
            fp.write(self.bytes.tobytes())      # write the whole pixels (remember self.bytes holds the image (array of pixels)
*/


//<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>\\
//                                                                                            \\
//                                                                                            \\
//                              Recreating the Scene class in C                               \\
//                                                                                            \\
//                                                                                            \\
//<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>\\


void init_scene(Scene* scene){
    scene->simple_spheres_count = 0;
    scene->simple_halfspaces_count = 0;
    scene->checker_spheres_count = 0;
    scene->checker_halfspaces_count = 0;
    scene->light_points_count = 0;
    init_point(&(scene->position), 0, 1.8, 10);
    init_point(&(scene->looking_at), 0, 0, 0);
    scene->field_of_view = 45.0;
    scene->recursion_depth = 0;
}

void move_to(Scene* scene, const Point* p){
    scene->position = *p;
}

void look_at(Scene* scene, const Point* p){
    scene->looking_at = *p;
}

void add_to_simple_spheres(Scene* scene, const Sphere* sphere, const Simple_Surface* surface){
    if (scene->simple_spheres_count < 10) {
        scene->simple_spheres[scene->simple_spheres_count].sphere = *sphere;
        scene->simple_spheres[scene->simple_spheres_count].surface = *surface;
        scene->simple_spheres_count++;
    } else {
        printf("Error: Maximum number of simple spheres reached.\n");
    }
}

void add_to_simple_halfspaces(Scene* scene, const Halfspace* halfspace, const Simple_Surface* surface){
    if (scene->simple_halfspaces_count < 10) {
        scene->simple_halfspaces[scene->simple_halfspaces_count].halfspace = *halfspace;
        scene->simple_halfspaces[scene->simple_halfspaces_count].surface = *surface;
        scene->simple_halfspaces_count++;
    } else {
        printf("Error: Maximum number of simple halfspaces reached.\n");
    }
}

void add_to_checker_spheres(Scene* scene, const Sphere* sphere, const Checkerboard_Surface* surface){
    if (scene->checker_spheres_count < 10) {
        scene->checker_spheres[scene->checker_spheres_count].sphere = *sphere;
        scene->checker_spheres[scene->checker_spheres_count].surface = *surface;
        scene->checker_spheres_count++;
    } else {
        printf("Error: Maximum number of checkerboard spheres reached.\n");
    }
}

void add_to_checker_halfspaces(Scene* scene, const Halfspace* halfspace, const Checkerboard_Surface* surface){
    if (scene->checker_halfspaces_count < 10) {
        scene->checker_halfspaces[scene->checker_halfspaces_count].halfspace = *halfspace;
        scene->checker_halfspaces[scene->checker_halfspaces_count].surface = *surface;
        scene->checker_halfspaces_count++;
    } else {
        printf("Error: Maximum number of checkerboard halfspaces reached.\n");
    }
}

/*
--- taken care of by the python code and the singular adders (add_to_simple_spheres, add_to_simple_halfspaces, add_to_checker_spheres, add_to_checker_halfspaces) ---
void add_object(Scene* scene, const void* object, const void* surface){
    if (isinstance(object, Sphere)) {
        if (isinstance(surface, SimpleSurface)) {
            add_to_simple_spheres(&scene, object, surface);
        } else if (isinstance(surface, CheckerboardSurface)) {
            add_to_checker_spheres(&scene, object, surface);
        }
    } else if (isinstance(object, Halfspace)) {
        if (isinstance(surface, SimpleSurface)) {
            add_to_simple_halfspaces(&scene, object, surface);
        } else if (isinstance(surface, CheckerboardSurface)) {
            add_to_checker_halfspaces(&scene, object, surface);
        }
    }
}
*/

void add_light(Scene* scene, const Point* point){
    if (scene->light_points_count < 10) {
        scene->light_points[scene->light_points_count] = *point;
        scene->light_points_count++;
    } else {
        printf("Error: Maximum number of light points was reached.\n");
    }
}


//<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>\\
//                                                                                            \\
//                                                                                            \\
//                      Defining the First Intersection Function in C                         \\
//                                                                                            \\
//                                                                                            \\
//<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>\\

void find_first_intersection(const Scene* scene, const Ray* ray, Min_Packer *result){
    result->min_type = 0;    // no intersection

    result->min_time = INFINITY;
    double temp_time;
    for (int i = 0; i < scene->simple_spheres_count; i++){
        temp_time = intersection_time_sphere(&(scene->simple_spheres[i].sphere), ray);
        if (temp_time < result->min_time && temp_time > -EPSILON) {
            result->min_time = temp_time;
            result->min_type = 1;
            result->min_simple_sphere = scene->simple_spheres[i];
        }
    }
    for (int i = 0; i < scene->checker_spheres_count; i++){
        temp_time = intersection_time_sphere(&(scene->checker_spheres[i].sphere), ray);
        if (temp_time < result->min_time && temp_time > -EPSILON) {
            result->min_time = temp_time;
            result->min_type = 2;
            result->min_checkerboard_sphere = scene->checker_spheres[i];
        }
    }
    for (int i = 0; i < scene->simple_halfspaces_count; i++){
        temp_time = intersection_time_halfspace(&(scene->simple_halfspaces[i].halfspace), ray);
        if (temp_time < result->min_time && temp_time > -EPSILON) {
            result->min_time = temp_time;
            result->min_type = 3;
            result->min_simple_halfspace = scene->simple_halfspaces[i];
        }
    }
    for (int i = 0; i < scene->checker_halfspaces_count; i++){
        temp_time = intersection_time_halfspace(&(scene->checker_halfspaces[i].halfspace), ray);
        if (temp_time < result->min_time && temp_time > -EPSILON) {
            result->min_time = temp_time;
            result->min_type = 4;
            result->min_checkerboard_halfspace = scene->checker_halfspaces[i];
        }
    }
}

/*
def firstIntersection(intersections):   # branchless logic?
    result = None
    for i in intersections:
        candidateT = i[1]
        if candidateT is not None and candidateT > -EPSILON:
            if result is None or candidateT < result[1]:
                result = i
    return result
*/


//<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>\\
//                                                                                            \\
//                                                                                            \\
//                    Defining the color Getter and Render Functions in C                     \\
//                                                                                            \\
//                                                                                            \\
//<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>----<>\\


// shooting (cursed technique) reversal light and tracking what object it hits, can bounce, but not more than the maximum recursion depth (3)
Double_Color ray_color(Scene* scene, const Ray* ray){
    if (scene->recursion_depth > 3){    // maximum recursion depth reached, return black
        return (Double_Color){0.0, 0.0, 0.0};
    }

    scene->recursion_depth++;
    Double_Color final_color = (Double_Color){0.0, 0.0, 0.0};
    
    // find the first intersection -----------------------------------------------------------------
    Min_Packer min_intersection_package;
    find_first_intersection(scene, ray, &min_intersection_package);

    // if min_type == 0, then no intersection was found, return black, which is already the final color
    if (min_intersection_package.min_type != 0) {
        Point p = point_at_time_creation(ray, min_intersection_package.min_time);
        if (min_intersection_package.min_type == 1){         // simple sphere
            Vector helper_vector = normal_at(&(min_intersection_package.min_simple_sphere.sphere), &p);
            final_color = color_at_simple_surface(scene, &(min_intersection_package.min_simple_sphere.surface), ray, &p, &helper_vector);
        } else if (min_intersection_package.min_type == 2){    // checkerboard sphere
            Vector helper_vector = normal_at(&(min_intersection_package.min_checkerboard_sphere.sphere), &p);
            final_color = color_at_checkerboard_surface(scene, &(min_intersection_package.min_checkerboard_sphere.surface), ray, &p, &helper_vector);
        } else if (min_intersection_package.min_type == 3){    // simple halfspace
            Vector helper_vector = min_intersection_package.min_simple_halfspace.halfspace.normal;
            final_color = color_at_simple_surface(scene, &(min_intersection_package.min_simple_halfspace.surface), ray, &p, &helper_vector);
        } else if (min_intersection_package.min_type == 4){    // checkerboard halfspace
            Vector helper_vector = min_intersection_package.min_checkerboard_halfspace.halfspace.normal;
            final_color = color_at_checkerboard_surface(scene, &(min_intersection_package.min_checkerboard_halfspace.surface), ray, &p, &helper_vector);
        }
    }
    scene->recursion_depth--;
    return final_color;
}

// shoot the "reversal" light beams and 
void render(Scene* scene, const Canvas* canvas){
    double fov_radians = M_PI * scene->field_of_view / 360.0;     // redundant division, change to pi * (FOV / 360.0)
    double half_width = tan(fov_radians);        // optimize trigo calcs (accuracy trade)?
    double half_height = (3 * half_width) / 4;           // *0.75 = * 3 >> 2
    double width = half_width * 2;                   // * 2 = shift left by 1
    double height = half_height * 2;                 // * 2 = shift left by
    double pixel_width = width / (canvas->width - 1);
    double pixel_height = height / (canvas->height - 1);

    Ray eye;
    Vector eye_vector = vector_from_1_to_2_creation(&scene->position, &scene->looking_at);
    normalize_vector(&eye_vector);
    init_ray(&eye, &(scene->position), &(eye_vector));
    Vector vp_right = cross_product(&(eye.vector), &(Vector_UP));
    normalize_vector(&vp_right);
    Vector vp_up = cross_product(&(vp_right), &(eye.vector));
    normalize_vector(&vp_up);

    Vector y_comp, x_comp;  // avoid creating a new object every time, reuse the same object
    Ray ray;                // avoid creating a new object every time, reuse the same object
    int i = 0;              // the index in the array corresponding to the pixel
    ray.point = eye.point;  
    for (int y = 0; y < canvas->height; y++){
        y_comp = scale_vector_creation(&vp_up, y * pixel_height - half_height);
        for (int x = 0; x < canvas->width; x++){
            x_comp = scale_vector_creation(&vp_right, x * pixel_width - half_width);
            add_vectors_inplace(&eye.vector, &x_comp, &ray.vector); 
            add_vectors_inplace(&ray.vector, &y_comp, &ray.vector);
            normalize_vector(&ray.vector);
            Double_Color color = ray_color(scene, &ray);
            // plot(canvas, x, y, color.r, color.g, color.b);
            // there's no need to divide the color and then call function, duplicate the logic here
            i = ((canvas->height - y - 1) * canvas->width + x) * 3;        // mult can be changed to shift by 8 and sub 1 - not it's not, double is built different
            canvas->bytes[i] = (unsigned char)fmax(0, fmin(255, (color.r * 255)));
            canvas->bytes[i + 1] = (unsigned char)fmax(0, fmin(255, (color.g * 255)));
            canvas->bytes[i + 2] = (unsigned char)fmax(0, fmin(255, (color.b * 255)));
        }
    }
}

int is_light_visible(const Scene* scene, const Point* light_point, const Point* p){
    Ray ray;
    Vector beam_direction = vector_from_1_to_2_creation(p, light_point);
    double distance_magnitude = magnitude(&beam_direction);
    normalize_vector(&beam_direction);
    init_ray(&ray, p, &beam_direction);
    Min_Packer min_intersection;
    find_first_intersection(scene, &ray, &min_intersection);
    if (min_intersection.min_type == 0 || distance_magnitude < min_intersection.min_time || min_intersection.min_time < EPSILON) {    // an intersection time of the vector's magnitude means it's exactly at the light source, as the vector isn't normalize
        return 1;    // no intersection found, light is visible
    }
    return 0;   // an intersection between source and object was found, light is not visible
}


/*
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
*/


/*
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
                    SimpleSurface(basecolor=(1, 1, 0)))
        for y in range(6):      # add 6 spheres  
            s.addObject(Sphere(Point(-3 - y * 0.4, 2.3, -5), 0.4),
                        SimpleSurface(basecolor=(y / 6.0, 1 - y / 6.0, 0.5)))
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
*/

/*
int main() {
    printf("hello world\n");
    return 0;
}
*/
