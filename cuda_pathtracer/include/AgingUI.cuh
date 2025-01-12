#pragma once
#include "AgingEffects.cuh"
#include <X11/Xlib.h>
#include <X11/Xutil.h>

class AgingUI {
private:
    RustParameters rust_params;
    PaintAgingParameters paint_params;
    Display* display_;
    Window window_;
    GC gc_;
    int screen_;
    bool show_window{true};

    // UI state
    float slider_positions[8];  // Store positions for all sliders
    bool dragging[8]{false};   // Track which slider is being dragged

    // Constants for UI layout
    static constexpr int WINDOW_WIDTH = 300;
    static constexpr int WINDOW_HEIGHT = 400;
    static constexpr int SLIDER_HEIGHT = 20;
    static constexpr int SLIDER_WIDTH = 200;
    static constexpr int MARGIN = 10;

public:
    AgingUI(Display* display) : display_(display) {
        screen_ = DefaultScreen(display_);

        // Create UI window
        window_ = XCreateSimpleWindow(display_, DefaultRootWindow(display_),
            0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, 1,
            BlackPixel(display_, screen_),
            WhitePixel(display_, screen_));

        // Select input events
        XSelectInput(display_, window_,
            ExposureMask | ButtonPressMask | ButtonReleaseMask |
            PointerMotionMask | KeyPressMask);

        // Create GC for drawing
        gc_ = XCreateGC(display_, window_, 0, nullptr);

        // Initialize slider positions
        resetParameters();

        // Show window
        XMapWindow(display_, window_);
    }

    ~AgingUI() {
        if (gc_) XFreeGC(display_, gc_);
        if (window_) XDestroyWindow(display_, window_);
    }

    void resetParameters() {
        // Initialize parameters with default values
        rust_params = RustParameters();
        paint_params = PaintAgingParameters();

        // Initialize slider positions
        slider_positions[0] = rust_params.oxidation_level;
        slider_positions[1] = rust_params.surface_roughness;
        slider_positions[2] = rust_params.pattern_scale / 10.0f;
        slider_positions[3] = paint_params.peeling_amount;
        slider_positions[4] = paint_params.crack_density;
        slider_positions[5] = paint_params.weathering;
    }

    void render() {
        if (!show_window) return;

        // Clear window
        XClearWindow(display_, window_);

        // Draw UI elements
        drawSliders();
        drawLabels();

        // Flush drawing commands
        XFlush(display_);
    }

    void processEvent(XEvent& event) {
        switch (event.type) {
            case ButtonPress:
                handleMousePress(event.xbutton);
                break;
            case ButtonRelease:
                handleMouseRelease(event.xbutton);
                break;
            case MotionNotify:
                handleMouseMotion(event.xmotion);
                break;
        }
    }

    // const RustParameters& getRustParams() const { return rust_params; }
    // const PaintAgingParameters& getPaintParams() const { return paint_params; }
    void getRustParams(RustParameters& params) const {
        params = rust_params;
    }

    void getPaintParams(PaintAgingParameters& params) const {
        params = paint_params;
    }

private:
    void drawSliders() {
        int y = MARGIN;

        // Draw rust parameter sliders
        for (int i = 0; i < 3; i++) {
            drawSlider("Rust Parameter " + std::to_string(i),
                      slider_positions[i], y);
            y += SLIDER_HEIGHT + MARGIN;
        }

        y += MARGIN * 2;  // Add space between sections

        // Draw paint aging parameter sliders
        for (int i = 3; i < 6; i++) {
            drawSlider("Paint Parameter " + std::to_string(i-3),
                      slider_positions[i], y);
            y += SLIDER_HEIGHT + MARGIN;
        }
    }

    void drawSlider(const std::string& label, float value, int y) {
        // Draw slider background
        XSetForeground(display_, gc_, BlackPixel(display_, screen_));
        XDrawRectangle(display_, window_, gc_,
            MARGIN, y, SLIDER_WIDTH, SLIDER_HEIGHT);

        // Draw slider position
        int pos = MARGIN + (int)(value * SLIDER_WIDTH);
        XFillRectangle(display_, window_, gc_,
            pos - 5, y, 10, SLIDER_HEIGHT);

        // Draw label
        XDrawString(display_, window_, gc_,
            MARGIN, y - 5, label.c_str(), label.length());
    }

    void drawLabels() {
        // Draw section headers
        XDrawString(display_, window_, gc_,
            MARGIN, MARGIN - 5, "Rust Parameters", 14);
        XDrawString(display_, window_, gc_,
            MARGIN, MARGIN * 8 - 5, "Paint Parameters", 15);
    }

    void handleMousePress(const XButtonEvent& event) {
        // Check if click is on a slider
        for (int i = 0; i < 6; i++) {
            if (isClickOnSlider(event.x, event.y, i)) {
                dragging[i] = true;
                updateSliderValue(i, event.x);
            }
        }
    }

    void handleMouseRelease(const XButtonEvent& event) {
        for (int i = 0; i < 6; i++) {
            dragging[i] = false;
        }
    }

    void handleMouseMotion(const XMotionEvent& event) {
        for (int i = 0; i < 6; i++) {
            if (dragging[i]) {
                updateSliderValue(i, event.x);
            }
        }
    }

    bool isClickOnSlider(int x, int y, int slider_index) {
        int slider_y = MARGIN + slider_index * (SLIDER_HEIGHT + MARGIN);
        if (slider_index >= 3) {
            slider_y += MARGIN * 2;
        }

        return x >= MARGIN && x <= MARGIN + SLIDER_WIDTH &&
               y >= slider_y && y <= slider_y + SLIDER_HEIGHT;
    }

    void updateSliderValue(int index, int x) {
        float value = (float)(x - MARGIN) / SLIDER_WIDTH;
        value = std::max(0.0f, std::min(1.0f, value));
        slider_positions[index] = value;

        // Update corresponding parameter
        switch (index) {
            case 0: rust_params.oxidation_level = value; break;
            case 1: rust_params.surface_roughness = value; break;
            case 2: rust_params.pattern_scale = value * 10.0f; break;
            case 3: paint_params.peeling_amount = value; break;
            case 4: paint_params.crack_density = value; break;
            case 5: paint_params.weathering = value; break;
        }
    }
};
