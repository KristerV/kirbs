export const Camera = {
  mounted() {
    this.video = this.el.querySelector("video")
    this.canvas = document.createElement("canvas")
    this.stream = null

    // Start camera when mounted
    this.startCamera()

    // Handle capture button clicks
    this.handleEvent("capture_photo", () => {
      this.capturePhoto()
    })
  },

  destroyed() {
    this.stopCamera()
  },

  async startCamera() {
    try {
      const constraints = {
        video: {
          facingMode: "environment", // Use back camera on mobile
        },
        audio: false
      }

      this.stream = await navigator.mediaDevices.getUserMedia(constraints)
      this.video.srcObject = this.stream
      this.video.play()

      // Wait for video to load metadata
      this.video.addEventListener("loadedmetadata", () => {
        this.canvas.width = this.video.videoWidth
        this.canvas.height = this.video.videoHeight
      })

    } catch (error) {
      console.error("Error accessing camera:", error)
      this.pushEvent("camera_error", { error: error.message })
    }
  },

  stopCamera() {
    if (this.stream) {
      this.stream.getTracks().forEach(track => track.stop())
    }
  },

  capturePhoto() {
    if (!this.video || !this.video.videoWidth) {
      console.error("Video not ready")
      return
    }

    // Draw current video frame to canvas
    const context = this.canvas.getContext("2d")
    context.drawImage(this.video, 0, 0, this.canvas.width, this.canvas.height)

    // Convert to blob
    this.canvas.toBlob((blob) => {
      const reader = new FileReader()
      reader.onloadend = () => {
        // Send base64 data to LiveView
        this.pushEvent("photo_captured", {
          data: reader.result,
          width: this.canvas.width,
          height: this.canvas.height
        })
      }
      reader.readAsDataURL(blob)
    }, "image/jpeg", 0.9)
  }
}
