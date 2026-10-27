trigger DemoStepTrigger on Demo_Step__e(after insert) {
  DemoStepHandler.handle(Trigger.new);
}
