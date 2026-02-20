export const SeasonalChart = {
  mounted() {
    const data = JSON.parse(this.el.dataset.chartData)
    const ctx = this.el.getContext("2d")

    const datasets = data.datasets.map((ds, i) => {
      const isLatest = i === data.datasets.length - 1
      const opacity = isLatest ? 1 : 0.15 + (i / data.datasets.length) * 0.5

      return {
        label: String(ds.year),
        data: ds.data,
        borderColor: `rgba(34, 197, 94, ${opacity})`,
        backgroundColor: `rgba(34, 197, 94, ${opacity * 0.1})`,
        borderWidth: isLatest ? 3 : 2,
        pointRadius: isLatest ? 4 : 2,
        pointHoverRadius: isLatest ? 6 : 4,
        tension: 0.3,
        spanGaps: true
      }
    })

    this.chart = new Chart(ctx, {
      type: "line",
      data: {
        labels: data.labels,
        datasets: datasets
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
            beginAtZero: true,
            title: {
              display: true,
              text: "Profit (€)"
            },
            grid: {
              color: "rgba(255, 255, 255, 0.1)"
            }
          }
        },
        plugins: {
          legend: {
            display: true,
            position: "bottom"
          },
          tooltip: {
            callbacks: {
              label: function(context) {
                return `${context.dataset.label}: €${Math.round(context.raw)}`
              }
            }
          }
        }
      }
    })
  },

  destroyed() {
    if (this.chart) {
      this.chart.destroy()
    }
  }
}
