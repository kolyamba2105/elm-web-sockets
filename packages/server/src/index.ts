import * as ws from 'ws'

const server = new ws.Server({ port: 8080 })

server.on('connection', socket => {
  console.log('Connection with client established...')

  socket.send(
    JSON.stringify({
      type: 'Init',
      payload: {
        role: 'Presenter',
        preferences: ['WebRTC', 'VNC'],
      },
    }),
  )

  // socket.send(
  //   JSON.stringify({ type: 'Init', payload: { role: 'Participant' } }),
  // )
  // socket.send(
  //   JSON.stringify({
  //     type: 'TransmissionState',
  //     payload: {
  //       status: 'Live',
  //       source: {
  //         label: 'Screen',
  //         id: '1',
  //         name: 'First',
  //       },
  //     },
  //   }),
  // )

  socket.onmessage = event => {
    if (typeof event.data === 'string') {
      const data = JSON.parse(event.data)

      console.log(data)

      switch (data.type) {
        case 'CreateConnection':
          switch (data.payload) {
            case 'WebRTC':
              return setTimeout(() => {
                socket.send(
                  JSON.stringify({
                    type: 'CreateConnectionResponse',
                    payload: {
                      technology: 'WebRTC',
                      isConnected: false,
                    },
                  }),
                )
              }, 1000)

            case 'VNC':
              return setTimeout(() => {
                socket.send(
                  JSON.stringify({
                    type: 'CreateConnectionResponse',
                    payload: {
                      technology: 'VNC',
                      isConnected: true,
                      isMobile: true,
                    },
                  }),
                )
              }, 1000)
          }

        case 'DropConnection':
          return setTimeout(() => {
            socket.send(JSON.stringify({ type: 'DropConnectionResponse' }))
          }, 1000)

        case 'StartTransmission':
        case 'ResumeTransmission':
          return setTimeout(() => {
            socket.send(
              JSON.stringify({
                type: 'TransmissionState',
                payload: {
                  status: 'Live',
                  source: data.payload,
                },
              }),
            )
          }, 1000)

        case 'PauseTransmission':
          return setTimeout(() => {
            socket.send(
              JSON.stringify({
                type: 'TransmissionState',
                payload: {
                  status: 'Paused',
                  source: data.payload,
                },
              }),
            )
          }, 1000)

        default:
          return undefined
      }
    }
  }
})
