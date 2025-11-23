function buildBurndownDatasets(burndownLines) {
  const now = new Date()
  const currentYear = now.getFullYear()
  const currentMonth = now.getMonth() + 1

  return burndownLines.map(([[year, month], values], index) => {
    const isCurrentMonth = year === currentYear && month === currentMonth
    return {
      label: index === 0 ? "Goal Remaining (€)" : "",
      data: values,
      type: "line",
      borderColor: isCurrentMonth ? "rgb(34, 197, 94)" : "rgba(34, 197, 94, 0.5)",
      backgroundColor: "transparent",
      borderDash: isCurrentMonth ? [] : [5, 5],
      tension: 0.3,
      fill: false,
      yAxisID: "y1",
      order: 0,
      spanGaps: false
    }
  })
}

function buildGhostDataset(ghostLine) {
  if (!ghostLine) return null
  return {
    label: "Last Month",
    data: ghostLine,
    type: "line",
    borderColor: "rgba(34, 197, 94, 0.3)",
    backgroundColor: "transparent",
    borderDash: [5, 5],
    tension: 0.3,
    fill: false,
    yAxisID: "y1",
    order: 1,
    spanGaps: false,
    pointRadius: 0
  }
}

export const DashboardChart = {
  mounted() {
    const ctx = this.el.getContext("2d")
    const data = JSON.parse(this.el.dataset.chartData)

    const burndownDatasets = buildBurndownDatasets(data.burndown_lines)
    const ghostDataset = buildGhostDataset(data.ghost_line)

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
          ...burndownDatasets,
          ...(ghostDataset ? [ghostDataset] : [])
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

    // Update burndown lines (remove old ones, add new ones)
    const burndownDatasets = buildBurndownDatasets(data.burndown_lines)
    const ghostDataset = buildGhostDataset(data.ghost_line)
    this.chart.data.datasets = [
      this.chart.data.datasets[0],
      this.chart.data.datasets[1],
      ...burndownDatasets,
      ...(ghostDataset ? [ghostDataset] : [])
    ]
    this.chart.update()
  },

  destroyed() {
    if (this.chart) {
      this.chart.destroy()
    }
  }
}
