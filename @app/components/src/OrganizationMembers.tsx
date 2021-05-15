import React, { useCallback, useState } from "react";
import {
  OrganizationPage_MembershipFragment,
  OrganizationPage_OrganizationFragment,
  SharedLayout_UserFragment,
  useInviteToOrganizationMutation,
  useRemoveFromOrganizationMutation,
  useTransferOrganizationOwnershipMutation,
} from "@app/graphql";
import { formItemLayout, tailFormItemLayout } from "@app/lib";
import * as Sentry from "@sentry/react";
import {
  Button,
  Card,
  Form,
  Input,
  List,
  message,
  Popconfirm,
  Typography,
} from "antd";
import Text from "antd/lib/typography/Text";
import useTranslation from "next-translate/useTranslation";
import { Store } from "rc-field-form/lib/interface";

import { Redirect } from "./index";

interface OrganizationMembersProps {
  currentUser?: SharedLayout_UserFragment | null;
  organization: OrganizationPage_OrganizationFragment;
  page: number;
  setPage: (newPage: number) => void;
}

export const ORGANIZATION_RESULTS_PER_PAGE = 10;

export const OrganizationMembers: React.FC<OrganizationMembersProps> = (
  props
) => {
  const { organization, currentUser, page, setPage } = props;

  const handlePaginationChange = (
    page: number
    //pageSize?: number | undefined
  ) => {
    setPage(page);
  };

  const renderItem = useCallback(
    (node: OrganizationPage_MembershipFragment) => (
      <OrganizationMemberListItem
        currentUser={currentUser}
        node={node}
        organization={organization}
      />
    ),
    [currentUser, organization]
  );

  const [inviteToOrganization] = useInviteToOrganizationMutation();
  const [inviteInProgress, setInviteInProgress] = useState(false);
  const [form] = Form.useForm();
  const handleInviteSubmit = useCallback(
    async (values: Store) => {
      if (inviteInProgress) {
        return;
      }
      const { inviteText } = values;
      setInviteInProgress(true);
      const isEmail = inviteText.includes("@");
      try {
        await inviteToOrganization({
          variables: {
            organizationId: organization.id,
            email: isEmail ? inviteText : null,
            username: isEmail ? null : inviteText,
          },
        });
        message.success(`'${inviteText}' invited.`);
        form.setFieldsValue({ inviteText: "" });
      } catch (e) {
        // TODO: handle this through the interface
        message.error(
          "Could not invite to organization: " +
            e.message.replace(/^GraphQL Error:/i, "")
        );
        Sentry.captureException(e);
      } finally {
        setInviteInProgress(false);
      }
    },
    [form, inviteInProgress, inviteToOrganization, organization.id]
  );

  if (!organization.currentUserIsOwner) {
    return (
      <Redirect
        as={`/admin/organization/${organization.slug}`}
        href="/admin/organization/[slug]"
      />
    );
  }

  return (
    <>
      <Card title="Invite new member">
        <Form {...formItemLayout} form={form} onFinish={handleInviteSubmit}>
          <Form.Item label="Username or email" name="inviteText">
            <Input
              disabled={inviteInProgress}
              placeholder="Enter username or email"
            />
          </Form.Item>
          <Form.Item {...tailFormItemLayout}>
            <Button disabled={inviteInProgress} htmlType="submit">
              Invite
            </Button>
          </Form.Item>
        </Form>
      </Card>
      <List
        dataSource={organization.organizationMemberships?.nodes ?? []}
        header={
          <Typography.Text style={{ fontSize: "16px" }} strong>
            Existing members
          </Typography.Text>
        }
        pagination={{
          current: page,
          pageSize: ORGANIZATION_RESULTS_PER_PAGE,
          total: organization.organizationMemberships?.totalCount,
          onChange: handlePaginationChange,
        }}
        renderItem={renderItem}
        size="large"
        style={{ marginTop: "2rem", borderColor: "#f0f0f0" }}
        bordered
      />
    </>
  );
};

interface OrganizationMemberListItemProps {
  node: OrganizationPage_MembershipFragment;
  organization: OrganizationPage_OrganizationFragment;
  currentUser?: SharedLayout_UserFragment | null;
}

const OrganizationMemberListItem: React.FC<OrganizationMemberListItemProps> = (
  props
) => {
  const { node, organization, currentUser } = props;

  const { t } = useTranslation("admin");
  const [removeMember] = useRemoveFromOrganizationMutation();
  const handleRemove = useCallback(async () => {
    try {
      await removeMember({
        variables: {
          organizationId: organization.id,
          userId: node.user?.id ?? 0,
        },
        refetchQueries: ["OrganizationMembers"],
      });
    } catch (e) {
      message.error("Error occurred when removing member: " + e.message);
      Sentry.captureException(e);
    }
  }, [node.user, organization.id, removeMember]);

  const [transferOwnership] = useTransferOrganizationOwnershipMutation();
  const handleTransfer = useCallback(async () => {
    try {
      await transferOwnership({
        variables: {
          organizationId: organization.id,
          userId: node.user?.id ?? 0,
        },
        refetchQueries: ["OrganizationMembers"],
      });
    } catch (e) {
      message.error("Error occurred when transferring ownership: " + e.message);
      Sentry.captureException(e);
    }
  }, [node.user, organization.id, transferOwnership]);

  const roles = [node.isOwner ? "owner" : null].filter(Boolean).join(" and ");
  return (
    <List.Item
      actions={[
        organization.currentUserIsOwner && node.user?.id !== currentUser?.id && (
          <Popconfirm
            key="remove"
            cancelText={t("common:no")}
            okText={t("common:yes")}
            title={`Are you sure you want to remove ${node.user?.name} from ${organization.name}?`}
            onConfirm={handleRemove}
          >
            <a>Remove</a>
          </Popconfirm>
        ),
        organization.currentUserIsOwner && node.user?.id !== currentUser?.id && (
          <Popconfirm
            key="transfer"
            cancelText={t("common:no")}
            okText={t("common:yes")}
            title={`Are you sure you want to transfer ownership of ${organization.name} to ${node.user?.name}?`}
            onConfirm={handleTransfer}
          >
            <a>Make owner</a>
          </Popconfirm>
        ),
      ].filter(Boolean)}
    >
      <List.Item.Meta
        //avatar={...}
        description={
          <div>
            <Text>{node.user?.username}</Text>
            {roles && (
              <div>
                <Text type="secondary">({roles})</Text>
              </div>
            )}
          </div>
        }
        title={node.user?.name}
      />
    </List.Item>
  );
};
