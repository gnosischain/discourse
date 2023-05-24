import { tracked } from "@glimmer/tracking";
import Service, { inject as service } from "@ember/service";
import { action } from "@ember/object";

export default class ChatComposer extends Service {
  @service chat;
  @service currentUser;

  @tracked message;

  @action
  cancel() {
    if (this.message.editing) {
      this.reset();
    } else if (this.message.inReplyTo) {
      this.message.inReplyTo = null;
    }
  }

  @action
  clear() {
    this.message.message = "";
  }

  @action
  editMessage(message) {
    this.chat.activeMessage = null;
    message.editing = true;
    this.message = message;
  }

  @action
  onCancelEditing() {
    this.reset();
  }
}
