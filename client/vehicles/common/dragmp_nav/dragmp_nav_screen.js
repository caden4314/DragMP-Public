(function () {
  const screen = document.getElementById('screen')
  const idleScreen = document.getElementById('idleScreen')
  const idleLogo = document.getElementById('idleLogo')
  const runScreen = document.getElementById('runScreen')
  const finishScreen = document.getElementById('finishScreen')
  const rt = document.getElementById('rt')
  const et = document.getElementById('et')
  const quarterTime = document.getElementById('quarterTime')
  const quarterMph = document.getElementById('quarterMph')
  const idle = {
    x: 24,
    y: 20,
    vx: 1.6,
    vy: 1.2,
    lastTime: 0
  }

  function fixed(value, decimals) {
    if (typeof value !== 'number' || !isFinite(value)) return '--'
    return value.toFixed(decimals)
  }

  function setPage(name) {
    idleScreen.className = name === 'idle' ? 'screen-page idle-page active' : 'screen-page idle-page'
    runScreen.className = name === 'run' ? 'screen-page active' : 'screen-page'
    finishScreen.className = name === 'finish' ? 'screen-page active' : 'screen-page'
  }

  function animateIdle(time) {
    if (!idle.lastTime) idle.lastTime = time
    const dt = Math.min(2.5, (time - idle.lastTime) / 16.667)
    idle.lastTime = time

    if (idleScreen.className.indexOf('active') !== -1) {
      const maxX = 512 - idleLogo.offsetWidth - 4
      const maxY = 256 - idleLogo.offsetHeight - 4
      idle.x += idle.vx * dt
      idle.y += idle.vy * dt
      if (idle.x <= 4 || idle.x >= maxX) {
        idle.vx *= -1
        idle.x = Math.max(4, Math.min(maxX, idle.x))
      }
      if (idle.y <= 4 || idle.y >= maxY) {
        idle.vy *= -1
        idle.y = Math.max(4, Math.min(maxY, idle.y))
      }
      idleLogo.style.transform = 'translate(' + idle.x.toFixed(1) + 'px, ' + idle.y.toFixed(1) + 'px)'
    }

    window.requestAnimationFrame(animateIdle)
  }

  window.requestAnimationFrame(animateIdle)

  window.updateDragMP = function updateDragMP(data) {
    data = data || {}
    const idleStatus = !data.status || data.status === 'WAITING'
    const finalStatus = data.status === 'FINISH' || data.status === 'WIN' || data.status === 'DQ'
    const hasFinishData = typeof data.quarterTime === 'number' || typeof data.quarterMph === 'number'
    const showFinish = finalStatus || hasFinishData
    if (idleStatus) {
      setPage('idle')
    } else if (showFinish) {
      setPage('finish')
    } else {
      setPage('run')
    }
    rt.textContent = fixed(data.reactionTime, 3)
    et.textContent = fixed(data.elapsedTime, 3)
    quarterTime.textContent = fixed(data.quarterTime, 3)
    quarterMph.textContent = fixed(data.quarterMph, 2)
    if (data.won) {
      screen.className = 'winner'
    } else if (showFinish) {
      screen.className = 'finished'
    } else if (idleStatus) {
      screen.className = 'idle'
    } else {
      screen.className = 'running'
    }
  }
}())
