# HTML5 GPU Showcase / Gem Room Benchmark

## Full Technical Specification

---

## 1. General Information

**Project name:** HTML5 GPU Showcase / Gem Room Benchmark
**Project type:** HTML5 application / interactive graphics showcase / browser benchmark
**Engine:** Defold
**Purpose:** to demonstrate the limits of modern HTML5/WebGL rendering across different devices, focusing on the most striking image possible achieved through the cleverest possible optimization

---

## 2. Project Purpose

The goal is to develop an HTML5 application on the Defold engine: a visually rich procedural 3D showcase that runs in the browser from a link and is used to test how far web rendering quality can be pushed on both modern and not-so-modern devices.

This project is not an ordinary game. It is an interactive showcase and, at the same time, a technical rendering benchmark. Its job is to demonstrate that even in HTML5 it is possible to achieve rendering that looks very expensive, provided it is built on carefully chosen approximations, procedural generation, analytic computation and a well-designed quality scaling system.

The main goal of the project:

> To show the most lavish, striking, “expensive-looking” image possible in HTML5, while keeping it fast and scalable enough to run on a wide range of devices.

---

## 3. Core Artistic and Technical Concept

The scene is a large cubic room containing the camera and a cloud of transparent, glittering, refractive objects that visually resemble gemstones, crystals or glass bodies.

The room has six interior faces. Each face has its own flat color. The colors should be mostly neutral, close to gray, though slight differences in hue are allowed. The ceiling is always white and always serves as the main emissive light source of the scene.

The room contains many procedural objects. These objects should visually look like expensive transparent gems, featuring:

* reflection,
* refraction,
* internal thickness,
* turbidity (cloudiness),
* internal glow,
* local chromatic aberration,
* bright specular highlights,
* cinematic depth of field in the scene.

At the same time, the project deliberately does not aim for physically perfect correctness. It should aim for **the most convincing and the cheapest possible imitation of complex optics**, sufficient to produce a strong visual effect.

---

## 4. Key Requirements

### 4.1. Mandatory Requirements

The project must:

* work as a Defold HTML5 build;
* launch from a URL without installation;
* generate the scene entirely procedurally at startup;
* display a technical HUD with performance metrics;
* include, at a later stage, an automatic quality reduction system;
* show a visually very rich gem material;
* use depth of field;
* support at least one simple and one advanced gem optics mode;
* demonstrate that complex web rendering can be fast.

### 4.2. Visual Requirement

The project should make the viewer think:

> “Wow, this actually runs in a browser?”

### 4.3. Design Philosophy Requirement

The project must be built not on brute force, but on a combination of:

* procedural generation,
* analytic rendering,
* cheap tricks,
* reuse of intermediate data,
* adaptive quality,
* fine-grained shader tuning.

---

## 5. Scene Composition

The scene consists of three main entities:

### 5.1. Cubic Room

A large interior cube that contains the camera and all objects.

### 5.2. Object Cloud

A set of procedural bodies that represent the future “gemstones” or glass objects.

### 5.3. Camera

The camera is located inside the cubic room, points at the group of objects and can be rotated by the user.

---

## 6. Cubic Room

### 6.1. General Concept

The room should be procedural and analytic. An actual 3D cube as a geometric object is not required. The preferred rendering method is a single fullscreen pass that computes, for each pixel, which face of the analytic cube the view ray hits.

### 6.2. Mandatory Room Properties

The room must have:

* six faces;
* a separate color for each face;
* a strictly white ceiling;
* the ceiling treated as emissive;
* walls and floor that may be gray or slightly shifted in hue.

### 6.3. Room Lighting

The room must not simply be flat-shaded. Analytic shading is required to create the impression that the white ceiling illuminates the other faces.

The following approaches are allowed and recommended:

* analytic computation of lighting from a square area light;
* very lightweight ray tracing against analytic geometry;
* a small number of mathematical samples;
* a short loop with no texture fetches.

### 6.4. Cost Constraints

The room shader must be cheap in terms of bandwidth and texture fetch cost. The richness of the image in this pass should come from math, not from texture samples.

### 6.5. Room Pass Outputs

The room pass must produce:

* scene color;
* depth;
* data suitable for subsequent depth of field;
* the initial frame contents for the subsequent gem rendering.

---

## 7. Procedural Objects

### 7.1. General Concept

All objects are generated procedurally at application startup.

### 7.2. Shape Types

In the early stages, it is enough to support simple shapes:

* sphere,
* cube,
* one polyhedron.

The set of shapes may be extended in later stages.

### 7.3. Object Scale

All objects should be roughly the same scale and fit within a known radius. This matters for:

* scene composition,
* thickness approximation,
* internal glow computation,
* computing the screen-space self-refraction exclusion,
* DOF autofocus.

### 7.4. Normals

Normal requirements:

* the sphere has smooth normals;
* the cube and the polyhedron have hard (flat) normals;
* at a later stage, crystals may have a complex faceted structure.

### 7.5. Object Center and Radius

Each object must have:

* a world-space center;
* an approximate bounding radius.

This data must be available to CPU-side logic and used in shaders, either directly or through auxiliary parameters.

---

## 8. Object and Camera Motion

### 8.1. Object Motion

In the final version, objects should move smoothly and slowly. The motion may be:

* a group rotation of the cloud,
* individual smooth trajectories,
* a combination of both approaches.

### 8.2. Nature of the Motion

The motion should be:

* slow;
* smooth;
* beautiful;
* free of abrupt accelerations;
* unobtrusive, so it does not interfere with appreciating the material.

### 8.3. Camera Control

The user must be able to rotate the camera with the mouse while holding a button. On mobile devices, with an equivalent gesture.

The camera should orbit around the center of the scene or around the object cloud so that the user can examine the material from different angles.

---

## 9. Overall Rendering Architecture

The project is built as a multi-pass rendering pipeline that can offer simple and advanced modes.

Main pipeline blocks:

1. Scene and camera update
2. Analytic room rendering
3. Object rendering
4. Frame composition
5. Post-processing
6. History buffer generation
7. At a later stage, adaptive quality scaling

---

## 10. Base Rendering Process

### 10.1. Scene Update

The following must be updated every frame:

* the camera;
* object positions/motion;
* autofocus parameters;
* history parameters;
* at a later stage, the adaptive quality system.

### 10.2. Room Rendering

The room is rendered analytically, preferably with a fullscreen pass.

### 10.3. Object Rendering

Objects are rendered as regular Defold game objects without any separate transparency sorting.

### 10.4. Post-Processing

After the frame is formed, the following are applied:

* pseudo-HDR decode,
* depth of field,
* at a later stage, FXAA,
* UI output.

### 10.5. History

There must be a low-resolution history buffer of the previous frame for use in screen-space reflection and refraction tracing.

---

## 11. The Key Feature of Transparency

This project **does not use conventional transparency**.

### 11.1. What This Means

Gems must not be rendered with ordinary translucency and must not use the standard alpha blending scheme as the basis of the material.

### 11.2. How the Sense of Transparency Is Created

The sense of transparency is created through:

* samples from the previous frame's history buffer;
* samples from the analytic cube;
* shader-based compositing of reflection and refraction;
* the material's thickness and color filtering.

### 11.3. Hardware Blending

The final rendering of the scene and the gems must be done **with blending disabled**. The alpha channel is used not for transparency but for a pseudo-HDR brightness multiplier.

### 11.4. Transparency Sorting

There will be no special sorting of transparent objects at all. Objects are rendered by the engine as ordinary opaque objects.

This is an architectural choice made for the sake of speed and pipeline simplicity.

---

## 12. Gem Material

The gem material is the centerpiece of the project. It should look expensive and complex, even though it is built on approximations.

### 12.1. The Material Must Include

* external reflection;
* internal refraction;
* Fresnel;
* internal thickness;
* turbidity;
* internal tint;
* local chromatic aberration;
* bright specular highlights;
* internal glow from above;
* in advanced mode, improved thickness and a backface/frontface scheme.

### 12.2. Prohibited Approach

Fullscreen chromatic aberration applied to the whole frame is prohibited.
Chromatic aberration must exist only as a local property of the gem material itself.

---

## 13. Thickness Approximation

### 13.1. Basic Cheap Model

For every gem pixel, a cheap estimate of the length of the view ray's path inside the object must be available.

The basis of the approximation:

* the object's center is known;
* the object's radius is known;
* the position of the current pixel relative to the center is known;
* if the ray passes closer to the center, the thickness is greater;
* if it is closer to tangent, the thickness is smaller.

### 13.2. Purpose of Thickness

Thickness should affect:

* color saturation;
* turbidity;
* refraction strength;
* the strength of internal color filtering;
* the strength of chromatic aberration;
* internal glow;
* possible pseudo-SSS.

---

## 14. Advanced Thickness Mode

For high/ultra quality, there must be an improved thickness estimation scheme.

### 14.1. Backface Pass

A separate reduced-resolution pass renders the back faces of the gems and stores data that makes it possible to reconstruct:

* the back surface normal;
* the back surface depth;
* the back surface world position, or data to reconstruct it.

### 14.2. Frontface Data

The front-face pass must have access to:

* the front surface normal;
* the front surface depth;
* the world position of the ray entry point, or data to reconstruct it.

### 14.3. Result

The front/back data must be used to compute:

* more accurate thickness;
* the ray exit point;
* the exit normal;
* a more plausible direction for the refracted ray.

### 14.4. Resolution

The backface pass must run at reduced resolution, for example:

* 1/2,
* 1/4 of the main internal resolution.

---

## 15. Reflection

### 15.1. Basic Mode

In simple mode, reflection is taken only from the analytic cube:

* the reflected ray is computed;
* its intersection with the cube is determined;
* the color of the corresponding face is selected;
* if needed, its lit variant is used.

### 15.2. Advanced Mode

In advanced mode, a short screen-space trace through the previous frame's history buffer is used.

Inputs:

* low-res history color;
* low-res history depth;
* reflected direction;
* a limited number of steps;
* a limited maximum ray length.

### 15.3. Tracing Parameters

Target tracing parameters:

* **4 to 8 samples per pixel**;
* **maximum ray length of roughly half the screen height**.

These parameters must be configurable.

### 15.4. Tuning

Shader parameters must make it possible to tune:

* the number of steps;
* the ray length;
* the step size;
* the strength of the fallback to the cube;
* the thresholds for accepting/rejecting the result.

### 15.5. Fallback

If tracing does not produce a valid hit, the reflection is taken from the analytic cube.

### 15.6. Visual Goal

Reflection should create the impression that the gems subtly reflect:

* the room walls,
* the ceiling,
* and, in advanced mode, other gems.

Physically correct SSR is not required.

---

## 16. Internal Refraction

### 16.1. Basic Mode

In simple mode, refraction is computed analytically against the cube:

* the refracted ray is computed;
* the ray is intersected with the analytic cube;
* the corresponding face color is selected.

### 16.2. Advanced Mode

In advanced mode, a short screen-space trace through the history buffer is performed in the direction of the refracted ray.

Inputs:

* history color;
* history depth;
* refracted direction;
* thickness estimate;
* in high mode, front/back surface data.

### 16.3. Tracing Parameters

Refraction must use the same classes of parameters as reflection:

* **4–8 samples per pixel**;
* **maximum ray length of up to half the screen height**;
* the parameters are tunable in the shader.

### 16.4. Fallback

If screen-space tracing does not produce a valid result, the analytic cube is used.

### 16.5. Compositing

The final color of a gem pixel must be composed from:

* reflection;
* refraction;
* thickness;
* turbidity;
* internal tint;
* Fresnel;
* specular highlights;
* local aberration;
* internal glow.

---

## 17. Self-Refraction and Self-Darkening Compensation

When using the history buffer, unwanted self-refraction is possible: an object may read its own image from the previous frame and gradually “turn black”.

A system to compensate for this effect must be implemented.

### 17.1. General Concept

After computing the screen-space point from which the history sample is to be read, it is necessary to check whether this point falls inside the screen-space projection of the current gem.

If it does:

* the history sample is considered invalid;
* the analytic cube is used instead.

### 17.2. Required Data

Each gem must have:

* the screen-space position of its center;
* a screen-space sampling exclusion radius.

It is preferable to prepare this data in the vertex shader and pass it to the fragment shader.

### 17.3. The Check

In the fragment shader, compute the distance between the history sample point and the screen-space center of the current gem.

If the distance is less than the screen-space exclusion radius, the sample is ignored.

### 17.4. Purpose

This is a cheap substitute for correct per-object transparent compositing and a mandatory part of a system based on whole-frame history.

---

## 18. Internal Tint and Turbidity

The material must support:

* internal color density;
* thickness-dependent transparency;
* turbidity;
* thickness-dependent turbidity;
* thickness-dependent saturation.

### 18.1. Mandatory Parameters

The following must be supported:

* base gem color;
* absorption coefficient;
* turbidity coefficient;
* thickness-based color gain coefficient;
* internal glow strength.

### 18.2. Visual Goal

Thin areas should be:

* more transparent,
* lighter.

Thick areas should be:

* more saturated,
* denser,
* richer and more noble in color.

---

## 19. Internal Glow from Above and Pseudo-SSS

### 19.1. General Concept

Since the main light source is always located above and its role is played by the ceiling, a cheap approximation of internal glow from above must be implemented.

### 19.2. Basis of the Approximation

The computation may use:

* the object's center position;
* the current pixel's position;
* the object's approximate radius;
* the known direction of light from above.

Based on this data, it is necessary to roughly estimate how much light has passed through the upper part of the volume to the current pixel.

### 19.3. Purpose

The effect should create the impression that the gem:

* glows slightly from within;
* has a lively translucent depth;
* does not look like cheap hollow glass.

### 19.4. Constraints

This is not physically correct SSS but a cheap artistic approximation. The effect should be:

* local;
* inexpensive;
* controllable;
* beautiful.

---

## 20. Local Chromatic Aberration

### 20.1. General Concept

Chromatic aberration must be a property of the gem material itself, not of the whole frame.

### 20.2. Dependencies

The effect should depend on:

* thickness;
* viewing angle;
* refraction strength;
* quality mode.

### 20.3. Implementation

A small offset between the R, G and B samples along the refraction direction is acceptable.

### 20.4. Constraint

The effect should be subtle and refined, not garish.

---

## 21. Pseudo-HDR in an LDR Pipeline

### 21.1. General Concept

The main pipeline should remain LDR to avoid expensive floating-point HDR render targets. At the same time, the impression of brighter light sources and highlights must be preserved.

### 21.2. Main Light Source

The main light source in the scene is the emissive ceiling.

Its brightness should drive:

* wall illumination;
* reflections;
* refractions;
* internal glow;
* the overall energy of the scene.

### 21.3. Storage Format

The main frame must be stored in RGBA8, where:

* RGB is the normalized color;
* A is the pixel's overall brightness multiplier.

### 21.4. Preferred Interpretation of the Alpha Channel

It is preferable to interpret the 8 bits of the alpha channel as:

* **3 integer bits**,
* **5 fractional bits**.

This is preferable to a 4+4 scheme, since the scene does not require an extremely wide HDR range, and a more precise fractional part is more useful.

### 21.5. Encode / Decode

There must be separate functions:

* `encodePseudoHDR()`
* `decodePseudoHDR()`

They are responsible for packing and unpacking the color and the brightness multiplier.

### 21.6. Constraints

Since alpha is used for brightness:

* scene alpha as transparency does not exist;
* blending is not used as the basis of scene transparency.

### 21.7. First Frame Initialization

For the history to be valid from the very start, the first history frame must be generated as a frame of the empty room without gems.

Only from the next frame onward should the gems use the history to create pseudo-transparency.

---

## 22. Depth of Field

### 22.1. Mandatory Status

Depth of field is a mandatory part of the project.

### 22.2. Nature of the DOF

The DOF must be dynamic and autofocusing rather than static.

### 22.3. Autofocus Algorithm

Every frame, a central ray is cast forward from the camera's center.

This ray is then tested for intersection with the gems using their known centers and radii.

### 22.4. Behavior

If the ray hits a gem:

* focus shifts to that gem;
* the depth of field narrows;
* the rest of the scene becomes more blurred.

If the ray does not hit any gem:

* focus shifts toward the center of the cloud;
* the depth of field widens;
* the blur decreases.

### 22.5. Smoothness

Focus must change smoothly.
Abrupt jumps in parameters must not be allowed.

The following must be applied:

* temporal smoothing;
* gradual easing of the focus distance;
* the feel of a live optical refocus.

### 22.6. Cost

In later stages, the DOF system must be able to scale down to a cheaper mode.

---

## 23. Adaptive Quality System

### 23.1. General Concept

The adaptive quality system is needed for the later stages of the project. It is not implemented in the first full “showpiece” stage.

### 23.2. Scaling Priority

Quality must scale down in two stages:

1. First, the internal rendering resolution is reduced
2. Only if that is not enough do effects start being simplified

### 23.3. Render Scale

The minimum internal scale is approximately **50%**.

### 23.4. Condition for Moving on to Cutting Effects

If, after the render scale has been lowered to its minimum, the FPS remains consistently insufficient, in particular below **30 FPS**, the system starts disabling and simplifying effects.

### 23.5. Scaling Order

Recommended order:

1. reduce the render scale;
2. simplify screen-space tracing;
3. disable the improved front/back scheme;
4. switch to analytic reflection and refraction;
5. simplify the DOF;
6. disable secondary material embellishments;
7. only at the very end, disable FXAA.

### 23.6. FXAA

FXAA should be kept as long as possible, because at a low render scale it helps hide pixelation.

It may be disabled only as a last resort.

---

## 24. Anti-Aliasing

### 24.1. Main Method

The main anti-aliasing method is a lightweight FXAA.

### 24.2. Priority

FXAA is a late stage of the optimization pipeline and may be absent from the very first full showpiece prototype.

### 24.3. Constraint

TAAU and other heavy temporal upsampling approaches are not required for the first version and must not complicate the base architecture.

---

## 25. History Buffer

### 25.1. General Concept

The history buffer is needed for:

* screen-space reflections;
* screen-space refractions;
* imitating transparency;
* cheaply reading back an already rendered frame.

### 25.2. Resolution

The history must be reduced in size. For example:

* 1/2,
* 1/4 of the internal render target.

### 25.3. What the History Stores

At a minimum, it must store:

* color;
* depth.

### 25.4. Source Requirement

The history must be captured from the clean frame, before the UI and before any final decorative distortions that could break the stability of the samples.

---

## 26. Shader Tuning Parameters

All key visual tuning parameters must be exposed as convenient shader parameters.

At a minimum, the following must be tunable:

* the number of reflection steps;
* the number of refraction steps;
* the maximum reflected ray length;
* the maximum refracted ray length;
* the step size;
* chromatic aberration strength;
* turbidity coefficient;
* thickness coefficient;
* internal glow strength;
* ceiling brightness;
* absorption coefficient;
* Fresnel strength;
* cube fallback parameters;
* the self-refraction exclusion threshold.

This is a mandatory requirement, since the project involves lengthy manual visual tuning.

---

## 27. Quality Modes

### 27.1. Low

* analytic cube only;
* analytic reflection only;
* analytic refraction only;
* basic thickness;
* simplified DOF;
* no history tracing;
* FXAA kept where possible.

### 27.2. Medium

* low-res history;
* short reflection and refraction traces;
* basic thickness;
* self-refraction compensation;
* standard DOF;
* FXAA.

### 27.3. High

* low-res history;
* backface pass;
* more accurate thickness;
* internal glow / pseudo-SSS;
* local chromatic aberration;
* improved DOF;
* FXAA.

### 27.4. Ultra

* maximum quality within the HTML5 budget;
* front/back scheme;
* maximum tracing steps within acceptable limits;
* full material;
* full self-refraction compensation;
* the best available DOF;
* FXAA.

---

## 28. User Interface

At a later stage, a technical HUD must be displayed on screen.

Minimum required elements:

* FPS;
* average frame time;
* current render scale;
* current preset;
* object count;
* internal render resolution;
* status of key effects.

Later on, it is desirable to add manual toggles:

* preset;
* DOF on/off;
* FXAA on/off;
* simple / advanced reflection;
* simple / advanced refraction;
* backface thickness on/off;
* object count;
* motion speed;
* DOF strength;
* auto quality on/off.

---

## 29. Architectural Constraints

The project must follow these rules:

* avoid real floating-point HDR render targets wherever the effect can be replaced with pseudo-HDR;
* avoid a fullscreen N-pass solution per gem;
* replace texture fetches with math wherever possible;
* make extensive use of half/quarter resolution for auxiliary buffers;
* the room pass must be as analytic as possible;
* every expensive mode must have a fallback;
* visual luxury must be the result of clever engineering, not brute force.

---

## 30. Main Modules and Components

The minimum set of project components:

* analytic room rendering module;
* camera control module;
* object generation module;
* history color/depth module;
* simple object shader;
* advanced gem material shader;
* backface pass shader;
* analytic ray–cube intersection functions;
* pseudo-HDR encode/decode functions;
* screen-space raymarch functions for reflection/refraction;
* depth of field module;
* later, an FXAA module;
* later, an adaptive quality module;
* HUD / debug overlay.

---

## 31. Development Stages

### Stage 1. Analytic Cubic Room and Camera

The first stage implements only the basic framework:

* analytic rendering of the cubic room;
* camera placement inside the room;
* the ability to rotate the camera with the mouse;
* displaying the scene on screen.

At this stage:

* no gems;
* no history;
* no DOF;
* no complex pipeline;
* no adaptive quality.

The goal of this stage is a beautiful, correct and convenient rendering of the cubic room.

---

### Stage 2. Procedural Objects Inside the Room

The second stage adds a set of simple procedural objects.

Stage requirements:

* objects are placed statically;
* they do not move;
* at least three shapes are used: sphere, cube, polyhedron;
* all objects are roughly the same scale;
* the sphere has smooth normals;
* the cube and the polyhedron have hard normals;
* the material is as simple as possible;
* each object has its own solid color;
* the color is passed via shader constants.
* there must be 12 objects in total: four of each type, each in a different color.

At this stage:

* no expensive shading;
* no history;
* no pseudo-HDR;
* no DOF;
* no screen-space tracing.

The goal of this stage is to verify the geometry, scale, composition and the basic scene.

---

### Stage 3. Full Showpiece Gem Pipeline

The third stage implements the project's main advanced rendering.

The following must be implemented:

* the gem material;
* reflections;
* refractions;
* history;
* analytic fallback to the cube;
* basic and/or advanced thickness;
* turbidity;
* internal color filtering;
* pseudo-HDR;
* local chromatic aberration;
* internal glow from above;
* depth of field;
* self-refraction compensation.

The following are **not implemented** at this stage:

* adaptive quality;
* quality profiles;
* FXAA;
* automatic quality reduction.

The goal of this stage is to first assemble the most beautiful and complete visual pipeline possible, and only then deal with quality scaling systems separately.

---

### Further Stages

Once the first three stages are complete, the further breakdown of tasks will be defined separately. Tentatively, the following can be expected:

* adaptive quality implementation;
* quality profiles;
* FXAA;
* UI/HUD;
* final tuning;
* extensive testing on real devices.

However, within the scope of this document, these stages are considered the next wave of planning.

---

## 32. Acceptance Criteria

The project can be considered successfully implemented if:

1. It runs in the browser as a Defold HTML5 application.
2. The scene is generated entirely procedurally.
3. The cubic room looks analytically lit rather than crudely flat-filled.
4. The objects visually look like expensive transparent gems.
5. The gems have reflection, refraction, thickness, turbidity and internal glow.
6. A history-based approach to pseudo-transparency is implemented.
7. Self-refraction compensation is implemented.
8. A dynamic autofocus DOF is implemented.
9. A quality reduction system is available at a later stage.
10. On capable devices, the image genuinely looks impressive.
11. On weak devices, the project does not “fall over” but scales down in a controlled way.

---

## 33. The Project in One Sentence

**HTML5 GPU Showcase / Gem Room Benchmark** is a procedural browser-based 3D showcase built on Defold that demonstrates the most striking and most optimized web rendering possible through an analytic cubic environment, a cloud of transparent gems, history-based pseudo-refraction and reflections, pseudo-HDR and a cinematic autofocus depth of field.
