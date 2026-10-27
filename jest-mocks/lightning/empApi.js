// Controllable mock of lightning/empApi for Jest.
const handlers = {};

export const subscribe = jest.fn((channel, replayId, onMessageCallback) => {
  handlers[channel] = onMessageCallback;
  return Promise.resolve({ id: `${channel}-sub`, channel, replayId });
});

export const unsubscribe = jest.fn((subscription, callback) => {
  delete handlers[subscription.channel];
  if (callback) {
    callback({ successful: true });
  }
  return Promise.resolve({ successful: true });
});

export const onError = jest.fn();
export const setDebugFlag = jest.fn();
export const isEmpEnabled = jest.fn(() => Promise.resolve(true));

/** Test helper: delivers a message to the subscriber of a channel. */
export const jestMockPublish = (channel, message) => {
  if (handlers[channel]) {
    handlers[channel](message);
    return true;
  }
  return false;
};
