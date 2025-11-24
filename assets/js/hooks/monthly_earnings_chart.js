export const MonthlyEarningsChart = {
  mounted() {
    const data = JSON.parse(this.el.dataset.chartData)

    const ctx = this.el.getContext("2d")

    this.chart = new Chart(ctx, {
      type: "bar",
      data: {
        labels: data.labels,
        datasets: [{
          data: data.values,
          backgroundColor: data.values.map((_, i) =>
            i === data.values.length - 1 ? "rgb(34, 197, 94)" : "rgba(34, 197, 94, 0.5)"
          ),
          borderRadius: 8,
          barThickness: 60
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            display: false
          },
          tooltip: {
            callbacks: {
              label: (context) => `€${context.raw}`
            }
          }
        },
        scales: {
          x: {
            grid: {
              display: false
            }
          },
          y: {
            beginAtZero: true,
            grid: {
              color: "rgba(255, 255, 255, 0.1)"
            },
            ticks: {
              callback: (value) => `€${value}`
            }
          }
        },
        animation: {
          onComplete: () => {
            this.drawLabels()
          }
        }
      }
    })
  },

  drawLabels() {
    const ctx = this.chart.ctx
    const meta = this.chart.getDatasetMeta(0)

    ctx.save()
    ctx.textAlign = "center"
    ctx.textBaseline = "middle"
    ctx.fillStyle = "white"
    ctx.font = "bold 14px sans-serif"

    meta.data.forEach((bar, i) => {
      const value = this.chart.data.datasets[0].data[i]
      if (value > 0) {
        const y = bar.y + (bar.base - bar.y) / 2
        ctx.fillText(`€${value}`, bar.x, y)
      }
    })

    ctx.restore()
  },

  updated() {
    const data = JSON.parse(this.el.dataset.chartData)
    this.chart.data.labels = data.labels
    this.chart.data.datasets[0].data = data.values
    this.chart.data.datasets[0].backgroundColor = data.values.map((_, i) =>
      i === data.values.length - 1 ? "rgb(34, 197, 94)" : "rgba(34, 197, 94, 0.5)"
    )
    this.chart.update()
  },

  destroyed() {
    if (this.chart) {
      this.chart.destroy()
    }
  }
}
