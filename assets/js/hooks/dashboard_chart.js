import Chart from "chart.js/auto"

export const DashboardChart = {
  mounted() {
    const ctx = this.el.getContext("2d")
    const data = JSON.parse(this.el.dataset.chartData)

    this.chart = new Chart(ctx, {
      type: "bar",
      data: {
        labels: data.labels,
        datasets: [
          {
            label: "Items Created",
            data: data.items_created,
            backgroundColor: "rgba(59, 130, 246, 0.6)",
            borderColor: "rgb(59, 130, 246)",
            borderWidth: 1,
            order: 1
          },
          {
            label: "Items Sold",
            data: data.items_sold,
            backgroundColor: "rgba(34, 197, 94, 0.6)",
            borderColor: "rgb(34, 197, 94)",
            borderWidth: 1,
            order: 2
          },
          {
            label: "Goal Remaining (€)",
            data: data.burndown,
            type: "line",
            borderColor: "rgb(34, 197, 94)",
            backgroundColor: "rgba(34, 197, 94, 0.1)",
            tension: 0.3,
            fill: false,
            yAxisID: "y1",
            order: 0
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        interaction: {
          mode: "index",
          intersect: false
        },
        scales: {
          y: {
            type: "linear",
            display: true,
            position: "left",
            title: {
              display: true,
              text: "Items"
            },
            beginAtZero: true
          },
          y1: {
            type: "linear",
            display: true,
            position: "right",
            title: {
              display: true,
              text: "Profit (€)"
            },
            beginAtZero: true,
            grid: {
              drawOnChartArea: false
            }
          }
        },
        plugins: {
          legend: {
            position: "bottom"
          }
        }
      }
    })
  },

  updated() {
    const data = JSON.parse(this.el.dataset.chartData)
    this.chart.data.labels = data.labels
    this.chart.data.datasets[0].data = data.items_created
    this.chart.data.datasets[1].data = data.items_sold
    this.chart.data.datasets[2].data = data.burndown
    this.chart.update()
  },

  destroyed() {
    if (this.chart) {
      this.chart.destroy()
    }
  }
}
