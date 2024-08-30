import Component from "@glimmer/component";
import { cached, tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { inject as service } from "@ember/service";
import { isEmpty, isPresent } from "@ember/utils";
import { and, eq } from "truth-helpers";
import SmallUserList from "discourse/components/small-user-list";
import UserTip from "discourse/components/user-tip";
import concatClass from "discourse/helpers/concat-class";
import { userPath } from "discourse/lib/url";
import i18n from "discourse-common/helpers/i18n";
import discourseLater from "discourse-common/lib/later";
import PostMenuBookmarkButton from "./buttons/bookmark";
import PostMenuCopyLinkButton from "./buttons/copy-link";
import EditButton from "./buttons/edit";
import LikeButton from "./buttons/like";
import PostMenuRepliesButton from "./buttons/replies";
import ReplyButton from "./buttons/reply";
import PostMenuShareButton from "./buttons/share";
import ShowMoreButton from "./buttons/show-more";

const LIKE_ACTION = 2;
const VIBRATE_DURATION = 5;

const ADMIN_BUTTON_ID = "admin";
const BOOKMARK_BUTTON_ID = "bookmark";
const COPY_LINK_BUTTON_ID = "copyLink";
const DELETE_BUTTON_ID = "delete";
const EDIT_BUTTON_ID = "edit";
const FLAG_BUTTON_ID = "flag";
const LIKE_BUTTON_ID = "like";
const READ_BUTTON_ID = "read";
const REPLIES_BUTTON_ID = "replies";
const REPLY_BUTTON_ID = "reply";
const SHARE_BUTTON_ID = "share";
const SHOW_MORE_BUTTON_ID = "showMore";

let registeredButtonComponents;
resetPostMenuButtons();

function resetPostMenuButtons() {
  registeredButtonComponents = new Map();

  registeredButtonComponents.set(ADMIN_BUTTON_ID, <template>
    <span>ADMIN</span>
  </template>);
  registeredButtonComponents.set(BOOKMARK_BUTTON_ID, PostMenuBookmarkButton);
  registeredButtonComponents.set(COPY_LINK_BUTTON_ID, PostMenuCopyLinkButton);
  registeredButtonComponents.set(DELETE_BUTTON_ID, <template>
    <span>DELETE</span>
  </template>);
  registeredButtonComponents.set(EDIT_BUTTON_ID, EditButton);
  registeredButtonComponents.set(FLAG_BUTTON_ID, <template>
    <span>FLAG</span>
  </template>);
  registeredButtonComponents.set(LIKE_BUTTON_ID, LikeButton);
  registeredButtonComponents.set(READ_BUTTON_ID, <template>
    <span>READ</span>
  </template>);
  registeredButtonComponents.set(REPLIES_BUTTON_ID, PostMenuRepliesButton);
  registeredButtonComponents.set(REPLY_BUTTON_ID, ReplyButton);
  registeredButtonComponents.set(SHARE_BUTTON_ID, PostMenuShareButton);
  registeredButtonComponents.set(SHOW_MORE_BUTTON_ID, ShowMoreButton);
}

export function clearExtraPostMenuButtons() {
  resetPostMenuButtons();
}

function smallUserAttributes(user) {
  return {
    template: user.avatar_template,
    username: user.username,
    post_url: user.post_url,
    url: userPath(user.username_lower),
    unknown: user.unknown,
  };
}

export default class PostMenu extends Component {
  @service capabilities;
  @service currentUser;
  @service keyValueStore;
  @service site;
  @service siteSettings;
  @service store;

  @tracked collapsed = true; // TODO some plugins will need a value transformer
  @tracked likedUsers = [];
  @tracked totalLikedUsers;
  @tracked readers = [];
  @tracked totalReaders;

  @cached
  get availableButtons() {
    return new Map(
      registeredButtonComponents.entries().map(([id, ButtonComponent]) => {
        let alwaysShow = false;
        let assignedAction;
        let properties;

        switch (id) {
          case COPY_LINK_BUTTON_ID:
            assignedAction = this.args.copyLink;
            break;

          case EDIT_BUTTON_ID:
            assignedAction = this.args.editPost;
            alwaysShow =
              this.#isWikiMode ||
              (this.args.transformedPost.canEdit &&
                this.args.transformedPost.yours);
            properties = {
              showLabel: this.site.desktopView && this.#isWikiMode,
            };
            break;

          case LIKE_BUTTON_ID:
            assignedAction = this.like;
            break;

          case REPLY_BUTTON_ID:
            assignedAction = this.args.replyToPost;
            properties = {
              showLabel: this.site.desktopView && !this.#isWikiMode,
            };
            break;

          case REPLIES_BUTTON_ID:
            assignedAction = this.args.toggleReplies;
            properties = {
              filteredRepliesView: this.args.filteredRepliesView,
              repliesShown: this.args.repliesShown,
            };
            break;

          case SHARE_BUTTON_ID:
            assignedAction = this.args.share;
            break;

          case SHOW_MORE_BUTTON_ID:
            assignedAction = this.showMoreActions;
            break;
        }

        const config = {
          postMenuButtonId: id,
          Component: ButtonComponent,
          action: assignedAction,
          alwaysShow,
          properties,
        };

        return [id, config];
      })
    );
  }

  get items() {
    return this.#configuredItems.map((i) => {
      // if the post is a wiki, make Edit more prominent
      if (this.#isWikiMode) {
        switch (i) {
          case EDIT_BUTTON_ID:
            return REPLY_BUTTON_ID;
          case REPLY_BUTTON_ID:
            return EDIT_BUTTON_ID;
        }
      }

      return i;
    });
  }

  get buttons() {
    return this.items
      .map((itemId) => this.availableButtons.get(itemId))
      .filter(isPresent);
  }

  @cached
  get collapsedButtons() {
    const hiddenItems = this.#hiddenItems;

    if (isEmpty(hiddenItems) || !this.collapsed) {
      return [];
    }

    return this.buttons.filter((button) => {
      if (button.alwaysShow) {
        return false;
      }

      if (
        this.args.transformedPost.reviewableId &&
        button.postMenuButtonId === FLAG_BUTTON_ID
      ) {
        return false;
      }

      return hiddenItems.includes(button.postMenuButtonId);
    });
  }

  get repliesButton() {
    return this.availableButtons.get(REPLIES_BUTTON_ID);
  }

  get shouldRenderRepliesButtonAutomatically() {
    // TODO check if the position is overridden using the DAG
    return this.repliesButton && !this.items.includes(REPLIES_BUTTON_ID);
  }

  get hasShowMoreButton() {
    // Only show ellipsis if there is more than one button hidden
    // if there are no more buttons, we are not collapsed
    return this.collapsedButtons.length > 1;
  }

  get showMoreButton() {
    return this.availableButtons.get(SHOW_MORE_BUTTON_ID);
  }

  get visibleButtons() {
    if (!this.hasShowMoreButton) {
      return this.buttons;
    }

    const buttons = this.buttons.filter((button) => {
      return !this.collapsedButtons.includes(button);
    });

    buttons.push(this.showMoreButton);

    return buttons;
  }

  get remainingLikedUsers() {
    return this.totalLikedUsers - this.likedUsers.length;
  }

  get remainingReaders() {
    return this.totalReaders - this.readers.length;
  }

  @action
  async like({ onBeforeToggle } = {}) {
    if (!this.currentUser) {
      this.keyValueStore &&
        this.keyValueStore.set({
          key: "likedPostId",
          value: this.args.transformedPost.id,
        });
      return this.sendWidgetAction("showLogin");
    }

    if (this.capabilities.userHasBeenActive && this.capabilities.canVibrate) {
      navigator.vibrate(VIBRATE_DURATION);
    }

    if (this.args.transformedPost.liked) {
      return this.args.toggleLike();
    }

    onBeforeToggle?.(this.args.transformedPost.liked);

    return new Promise((resolve) => {
      discourseLater(async () => {
        await this.args.toggleLike();
        resolve();
      }, 400);
    });
  }

  @action
  async showMoreActions() {
    this.collapsed = false;

    const fetchData = [
      !this.likedUsers.length && this.#fetchWhoLiked(),
      !this.readers.length &&
        this.args.transformedPost.showReadIndicator &&
        this.#fetchWhoRead(),
    ].filter(Boolean);

    await Promise.all(fetchData);
  }

  get #configuredItems() {
    return this.siteSettings.post_menu.split("|").filter(Boolean);
  }

  get #hiddenItems() {
    const setting = this.siteSettings.post_menu_hidden_items;

    if (isEmpty(setting)) {
      return [];
    }

    return setting
      .split("|")
      .filter(
        (itemId) =>
          !this.args.transformedPost.bookmarked || itemId !== BOOKMARK_BUTTON_ID
      );
  }

  get #isWikiMode() {
    return this.args.transformedPost.wiki && this.args.transformedPost.canEdit;
  }

  async #fetchWhoLiked() {
    const users = await this.store.find("post-action-user", {
      id: this.args.transformedPost.id,
      post_action_type_id: LIKE_ACTION,
    });

    this.likedUsers = users.map(smallUserAttributes);
    this.totalLikedUsers = users.totalRows;
  }

  async #fetchWhoRead() {
    const users = await this.store.find("post-reader", {
      id: this.args.transformedPost.id,
    });

    this.readers = users.map(smallUserAttributes);
    this.totalReaders = users.totalRows;
  }

  <template>
    <section class="post-menu-area clearfix">
      <nav
        class={{concatClass
          "post-controls"
          (if this.hasShowMoreButton "collapsed" "expanded")
          (if
            this.siteSettings.enable_filtered_replies_view
            "replies-button-visible"
          )
        }}
      >
        {{#if this.shouldRenderRepliesButtonAutomatically}}
          <this.repliesButton.Component
            class="btn-flat"
            @model={{@model}}
            @transformedPost={{@transformedPost}}
            @properties={{this.repliesButton.properties}}
            @action={{this.repliesButton.action}}
          />
        {{/if}}
        <div class="actions">
          {{#each this.visibleButtons as |button|}}
            <button.Component
              class="btn-flat"
              @model={{@model}}
              @transformedPost={{@transformedPost}}
              @properties={{button.properties}}
              @action={{button.action}}
            />
          {{/each}}
        </div>
      </nav>
      {{#if this.readers}}
        <SmallUserList
          class="who-read"
          aria-label={{i18n
            "post.actions.people.sr_post_readers_list_description"
          }}
          @users={{this.readers}}
          @addSelf={{false}}
          @count={{if
            this.remainingReaders
            this.remainingReaders
            this.totalReaders
          }}
          @description={{if
            this.remainingReaders
            "post.actions.people.read_capped"
            "post.actions.people.read"
          }}
        />
      {{/if}}
      {{#if this.likedUsers}}
        <SmallUserList
          class="who-liked"
          aria-label={{i18n
            "post.actions.people.sr_post_likers_list_description"
          }}
          @users={{this.likedUsers}}
          @addSelf={{and
            @transformedPost.liked
            (eq this.remainingLikedUsers 0)
          }}
          @count={{if
            this.remainingLikedUsers
            this.remainingLikedUsers
            this.totalLikedUsers
          }}
          @description={{if
            this.remainingLikedUsers
            "post.actions.people.like_capped"
            "post.actions.people.like"
          }}
        />
      {{/if}}
      {{#if this.hasShowMoreButton}}
        <UserTip
          @id="post_menu"
          @triggerSelector=".post-controls .actions .show-more-actions"
          @placement="top"
          @titleText={{i18n "user_tips.post_menu.title"}}
          @contentText={{i18n "user_tips.post_menu.content"}}
        />
      {{/if}}
    </section>
  </template>
}