const barLabelPlugin = {
  id: 'dailyBarLabels',
  afterDatasetsDraw(chart) {
    const ctx = chart.ctx
    ctx.save()
    ctx.textAlign = "center"
    ctx.textBaseline = "bottom"
    ctx.font = "bold 16px sans-serif"
    ctx.fillStyle = "#fff"

    chart.data.datasets.forEach((dataset, datasetIndex) => {
      const meta = chart.getDatasetMeta(datasetIndex)
      meta.data.forEach((bar, i) => {
        const value = dataset.data[i]
        if (value > 0) {
          ctx.fillText(value, bar.x, bar.y - 8)
        }
      })
    })

    ctx.restore()
  }
}

export const DailyChart = {
  mounted() {
    const data = JSON.parse(this.el.dataset.chartData)
    const ctx = this.el.getContext("2d")

    this.chart = new Chart(ctx, {
      type: "bar",
      data: {
        labels: data.labels,
        datasets: [
          {
            label: "Bags",
            data: data.bags,
            backgroundColor: "rgb(60, 100, 170)",
            borderRadius: 4,
            yAxisID: "y"
          },
          {
            label: "Bags with Items",
            data: data.bags_with_items,
            backgroundColor: "rgb(96, 165, 250)",
            borderRadius: 4,
            yAxisID: "y"
          },
          {
            label: "Items",
            data: data.items,
            backgroundColor: "rgb(140, 175, 210)",
            borderRadius: 4,
            yAxisID: "y"
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: false,
        hover: {
          mode: null
        },
        interaction: {
          mode: "index",
          intersect: false
        },
        scales: {
          x: {
            grid: {
              display: false
            }
          },
          y: {
            type: "linear",
            display: true,
            position: "left",
            beginAtZero: true,
            title: {
              display: true,
              text: "Count"
            },
            grid: {
              color: "rgba(255, 255, 255, 0.1)"
            }
          },
        },
        plugins: {
          legend: {
            display: true,
            position: "bottom"
          },
          tooltip: {
            enabled: false
          }
        }
      },
      plugins: [barLabelPlugin]
    })
  },

  destroyed() {
    if (this.chart) {
      this.chart.destroy()
    }
  }
}
