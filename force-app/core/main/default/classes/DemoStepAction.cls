/**
 * Lets record-triggered flows put their own step on the demo timeline. A flow calls the action once
 * per interview; interviews of the same batch are folded into one step per run and label.
 */
public with sharing class DemoStepAction {
  public class Input {
    @InvocableVariable(required=true label='Run Key')
    public String runKey;
    @InvocableVariable(required=true label='Demo Name')
    public String demoName;
    @InvocableVariable(label='Mode')
    public String mode;
    @InvocableVariable(required=true label='Step Label')
    public String label;
    @InvocableVariable(label='Message')
    public String message;
  }

  @InvocableMethod(
    label='Publish Demo Step'
    description='Publishes a Demo_Step__e for the portfolio demo panel timeline.'
    category='Portfolio Demo'
  )
  public static void publish(List<Input> inputs) {
    Map<String, Input> firstByStep = new Map<String, Input>();
    Map<String, Integer> countByStep = new Map<String, Integer>();
    for (Input input : inputs) {
      if (input == null || String.isBlank(input.runKey)) {
        continue;
      }
      String key = input.runKey + '|' + input.label;
      if (!firstByStep.containsKey(key)) {
        firstByStep.put(key, input);
        countByStep.put(key, 0);
      }
      countByStep.put(key, countByStep.get(key) + 1);
    }
    for (String key : firstByStep.keySet()) {
      Input input = firstByStep.get(key);
      DemoRunService.Request request = new DemoRunService.Request(
        input.demoName,
        input.mode,
        null
      );
      request.runKey = input.runKey;
      new DemoStepPublisher(request, null)
        .step(input.label, countByStep.get(key), 0, input.message);
    }
  }
}
