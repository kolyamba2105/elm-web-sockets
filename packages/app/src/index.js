import './main.css'
import { Elm } from './Main.elm'
import * as serviceWorker from './serviceWorker'

const app = Elm.Main.init({
  node: document.getElementById('root'),
})

const socket = new WebSocket('ws://localhost:8080')

socket.onmessage = event => {
  const data = JSON.parse(event.data)
  console.log(data)

  switch (data.type) {
    case 'Init':
      return app.ports.getInitialConfig.send(data.payload)

    case 'CreateConnectionResponse':
      return app.ports.getCreateConnectionResponse.send(data.payload)

    case 'DropConnectionResponse':
      return app.ports.getDropConnectionResponse.send(data.payload)

    case 'TransmissionState':
      return app.ports.getTransmissionState.send(data.payload)

    default:
      return undefined
  }
}

app.ports.createConnection.subscribe(technology => {
  socket.send(
    JSON.stringify({
      type: 'CreateConnection',
      payload: technology,
    }),
  )
})

app.ports.dropConnection.subscribe(() => {
  socket.send(JSON.stringify({ type: 'DropConnection' }))
})

app.ports.startTransmission.subscribe(source => {
  socket.send(JSON.stringify({ type: 'StartTransmission', payload: source }))
})

app.ports.pauseTransmission.subscribe(payload => {
  socket.send(JSON.stringify({ type: 'PauseTransmission', payload }))
})

app.ports.resumeTransmission.subscribe(payload => {
  socket.send(JSON.stringify({ type: 'ResumeTransmission', payload }))
})

// If you want your app to work offline and load faster, you can change
// unregister() to register() below. Note this comes with some pitfalls.
// Learn more about service workers: https://bit.ly/CRA-PWA
serviceWorker.unregister()
