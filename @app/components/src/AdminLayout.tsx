import * as qs from "querystring";

import React, { useState } from "react";
import PlusCircleTwoTone from "@ant-design/icons/PlusCircleTwoTone";
import { QueryResult } from "@apollo/client";
import { SharedLayout_QueryFragment } from "@app/graphql";
import { Layout } from "antd";
import { useRouter } from "next/router";
import useTranslation from "next-translate/useTranslation";

import { AdminSideMenu, MenuItem } from "./AdminSideMenu";
import { Redirect } from "./Redirect";
import {
  AuthRestrict,
  contentMinHeight,
  SharedLayout,
  SharedLayoutChildProps,
} from "./SharedLayout";
import { StandardWidth } from "./StandardWidth";

const { Sider, Content } = Layout;

const findPage = (key: string, items: MenuItem[]): MenuItem | undefined => {
  if (items?.some((item) => item.key === key)) {
    return items.find((item) => item.key === key);
  }
  const itemsWithChildren = items.filter(
    (item) =>
      typeof item.target !== "string" && typeof item.target !== "function"
  );
  for (let i = 0; i < itemsWithChildren.length; i++) {
    const res = findPage(key, itemsWithChildren[i].target as MenuItem[]);
    if (res) {
      return res;
    }
  }
  return undefined;
};

export interface AdminLayoutProps {
  query: Pick<
    QueryResult<SharedLayout_QueryFragment>,
    "data" | "loading" | "error" | "networkStatus" | "client" | "refetch"
  >;
  href: string;
  children: React.ReactNode;
}

export function AdminLayout({
  query,
  href: inHref,
  children,
}: AdminLayoutProps) {
  const { t } = useTranslation("admin");
  const [siderCollapsed, setSiderCollapsed] = useState(false);

  const basicMenuItems = [
    {
      key: "/admin",
      title: t("sider.titles.main"),
      target: "/admin",
    },
    {
      key: "/admin/emails",
      title: t("sider.titles.emails"),
      target: "/admin/emails",
    },
  ];

  const organizationMemberships =
    query.data?.currentUser?.organizationMemberships.nodes;

  const items: MenuItem[] = query.loading
    ? [...basicMenuItems]
    : [
        ...basicMenuItems,
        {
          key: "admin-menu-organizations",
          title: t("sider.titles.organizations"),
          cy: "admin-sider-organizations",
          target: organizationMemberships
            ? [
                ...organizationMemberships?.map(
                  (organization): MenuItem => {
                    const title = organization.organization?.name || "";
                    const slug = organization.organization?.slug;
                    return {
                      title,
                      key: `/admin/organization/${slug}`,
                      target: `/admin/organization/${slug}`,
                    };
                  }
                ),
                {
                  title: t("sider.titles.createOrganization"),
                  cy: "admin-sider-create-organization",
                  key: "/admin/organization/create",
                  target: "/admin/organization/create",
                  icon: <PlusCircleTwoTone twoToneColor="#52c41a" />,
                },
              ]
            : null,
        },
        {
          key: "admin-menu-events",
          title: t("sider.titles.events"),
          cy: "admin-sider-events",
          target: [
            {
              title: t("sider.titles.listEvents"),
              key: "/admin/event/list",
              target: "/admin/event/list",
            },
            {
              title: t("sider.titles.createEvent"),
              key: "/admin/event/create",
              target: "/admin/event/create",
              cy: "admin-sider-create-event",
              icon: <PlusCircleTwoTone twoToneColor="#52c41a" />,
            },
          ],
        },
        {
          key: "admin-menu-event-categories",
          title: t("sider.titles.eventCategories"),
          target: [
            {
              title: t("sider.titles.listEventCategories"),
              key: "/admin/event-category/list",
              target: "/admin/event-category/list",
            },
            {
              title: t("sider.titles.createEventCategory"),
              key: "/admin/event-category/create",
              target: "/admin/event-category/create",
              icon: <PlusCircleTwoTone twoToneColor="#52c41a" />,
            },
          ],
        },
      ];

  const page = findPage(String(inHref), items) || items[0];
  const href = page.key;

  const router = useRouter();
  const fullHref =
    href + (router && router.query ? `?${qs.stringify(router.query)}` : "");

  return (
    <SharedLayout
      forbidWhen={AuthRestrict.NOT_ADMIN}
      query={query}
      title={`${t("admin")}`}
      noPad
    >
      {({ currentUser, error, loading }: SharedLayoutChildProps) =>
        !currentUser && !error && !loading ? (
          <Redirect href={`/login?next=${encodeURIComponent(fullHref)}`} />
        ) : (
          <Layout style={{ minHeight: contentMinHeight }} hasSider>
            <Sider
              collapsed={siderCollapsed}
              collapsible
              onCollapse={(collapsed) => setSiderCollapsed(collapsed)}
            >
              <AdminSideMenu initialKey={href} items={items} />
            </Sider>
            <Content>
              <StandardWidth>{children}</StandardWidth>
            </Content>
          </Layout>
        )
      }
    </SharedLayout>
  );
}
